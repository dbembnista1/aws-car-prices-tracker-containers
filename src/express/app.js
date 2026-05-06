const AWS = require('aws-sdk');
const express = require('express');
const { ChartJSNodeCanvas } = require('chartjs-node-canvas');
const path = require('path');
const moment = require('moment'); // Import Moment.js
require('chartjs-adapter-moment'); // Import the moment adapter

// Set up DynamoDB client
AWS.config.update({ region: 'eu-central-1' }); // Change to your region
const dynamodb = new AWS.DynamoDB.DocumentClient();
const tableName = 'car_prices'; // Replace with your DynamoDB table name

// Express setup
const app = express();
const port = 3000;

// Serve static files from the "public" directory
app.use(express.static('public'));

// Chart.js setup
const width = 800; // width of the chart
const height = 600; // height of the chart
const chartJSNodeCanvas = new ChartJSNodeCanvas({ width, height });

// Helper function to calculate Simple Moving Average (SMA)
function movingAverage(data, windowSize) {
  const result = [];
  for (let i = 0; i < data.length; i++) {
    if (i < windowSize - 1) {
      result.push(null);
      continue;
    }
    let sum = 0;
    for (let j = 0; j < windowSize; j++) {
      sum += data[i - j];
    }
    result.push(sum / windowSize);
  }
  return result;
}

app.get('/', async (req, res) => {
  const params = {
    TableName: tableName
  };

  try {
    const data = await dynamodb.scan(params).promise();
    const items = data.Items;

    const carModels = new Set();
    items.forEach(item => {
      Object.keys(item).forEach(key => {
        if (key !== 'date') { 
          carModels.add(key);
        }
      });
    });

    const charts = {};
    for (const model of carModels) {
      const dates = [];
      const prices = [];

      items.forEach(item => {
        if (item[model]) {
          dates.push(item.date);
          prices.push(Number(item[model]));
        }
      });

      if (dates.length > 0) {
        // Parse and sort data by date
        const sortedData = dates.map((date, i) => ({
          date: moment(date, 'YYYY-MM-DD HH:mm:ss').toDate(),
          price: prices[i]
        })).sort((a, b) => a.date - b.date);

        const sortedPrices = sortedData.map(data => data.price);

        const smaWindow = 7; // Moving average window: 7 days
        const movingAvgPrices = movingAverage(sortedPrices, smaWindow);

        const configuration = {
          type: 'line',
          data: {
            labels: sortedData.map(data => data.date),
            datasets: [
              {
                label: `${model} (Original)`,
                data: sortedPrices,
                fill: false,
                borderColor: 'rgba(200, 200, 200, 0.4)',
                borderWidth: 1,
                pointRadius: 1,
                tension: 0 // Zmiana z 0.1 na 0 (wyłącza zakrzywienia)
              },
              {
                label: `${model} (${smaWindow}-day Moving Average)`,
                data: movingAvgPrices,
                fill: false,
                borderColor: 'rgba(75, 192, 192, 1)',
                borderWidth: 3,
                tension: 0, // Zmiana z 0.4 na 0 (wyłącza zakrzywienia)
                pointRadius: 0,
                spanGaps: true
              }
            ]
          },
          options: {
            scales: {
              x: {
                type: 'time',
                time: {
                  unit: 'month', // ZMIANA: Skala ustawiona na miesiące
                  displayFormats: {
                    month: 'MMM YYYY' // ZMIANA: Format wyświetlania (np. Mar 2025)
                  },
                  tooltipFormat: 'YYYY-MM-DD HH:mm:ss',
                },
                ticks: {
                  maxTicksLimit: 12 // Opcjonalne ograniczenie liczby etykiet, żeby uniknąć tłoku
                }
              }
            },
            plugins: {
              legend: {
                display: true
              }
            }
          }
        };

        const image = await chartJSNodeCanvas.renderToBuffer(configuration);
        charts[model] = image.toString('base64');
      }
    }

    let htmlContent = `
      <html>
        <head>
          <title>Car price change over time</title>
          <style>
            body { font-family: Arial, sans-serif; text-align: center; }
            img { max-width: 100%; border: 1px solid #ddd; margin-bottom: 30px; }
            h1 { margin-bottom: 5px; }
            h4 { font-weight: normal; color: #555; margin-top: 0; margin-bottom: 40px; }
          </style>
        </head>
        <body>
          <h1>Car price change over time</h1>
          <h4>(all models are from 2019 - we want to check if they are getting cheaper with time or the inflation/quality keep the price high)</h4>
          <a href="/api-form-with-authentication-hostedUI.html">API access</a><br><br>
    `;

    for (const [model, chart] of Object.entries(charts)) {
      htmlContent += `<h2>${model}</h2>`;
      htmlContent += `<img src="data:image/png;base64,${chart}" alt="${model} chart">`;
    }

    htmlContent += '</body></html>';
    res.send(htmlContent);

  } catch (err) {
    console.error('Error fetching data from DynamoDB', err);
    res.status(500).send('Error generating charts');
  }
});

app.listen(port, () => {
  console.log(`Server is running at http://localhost:${port}`);
});
