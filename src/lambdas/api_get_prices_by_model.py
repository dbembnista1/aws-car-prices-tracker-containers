import boto3
import json
from boto3.dynamodb.conditions import Key
from decimal import Decimal
from datetime import datetime

# Initialize the DynamoDB client
dynamodb = boto3.resource('dynamodb')

def get_car_prices_by_model(table_name, car_model):
    # Get reference to the table
    table = dynamodb.Table(table_name)

    try:
        response = table.scan(
            ProjectionExpression="#dt, #model",
            ExpressionAttributeNames={
                "#dt": "date",   # Mapping reserved keyword to an alias
                "#model": car_model
            }
        )

        # Prepare the result with only date and price
        formatted_items = []
        for item in response['Items']:
            # Check if the car_model key exists in the item
            if car_model in item:
                # Extract the date part only (remove the time)
                date_str = item["date"].split()[0]
                formatted_items.append({
                    "date": date_str, 
                    "price": float(item[car_model])
                })

        # Sort the formatted_items by date (zmieniony format)
        sorted_items = sorted(formatted_items, key=lambda x: datetime.strptime(x["date"], "%Y-%m-%d"))

        return sorted_items
    except Exception as e:
        # Handle the exception and return an error message
        print("Error fetching data from DynamoDB:", str(e))
        return []

def lambda_handler(event, context):
    # Extract the car model from the query string parameters
    car_model = event.get('queryStringParameters', {}).get('model', None)
    
    # If car_model is not provided, return an error
    if not car_model:
        return {
            'statusCode': 400,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps('car_model is required')
        }
    
    # Set the DynamoDB table name
    table_name = 'car_prices'  # Replace with your actual DynamoDB table name
    
    # Get the car prices by model
    result = get_car_prices_by_model(table_name, car_model)
    
    # Return the result as a JSON response with CORS headers
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,OPTIONS'
        },
        'body': json.dumps(result, indent=4)
    }