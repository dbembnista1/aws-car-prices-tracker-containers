import json
import boto3
import os

# Initialize the SNS client
sns = boto3.client('sns')

def lambda_handler(event, context):
    # DYNAMICZNY ARN POBIERANY Z TERRAFORMA
    topic_arn = os.environ.get('OUTPUT_SNS_TOPIC_ARN')
    if not topic_arn:
        raise ValueError("Missing OUTPUT_SNS_TOPIC_ARN environment variable")

    # Extract the response payload from the event
    print(event)
    
    # Accessing the first record
    sns_message = event['Records'][0]['Sns']['Message']
    
    # The message is a JSON string, so parse it into a dictionary
    message_dict = json.loads(sns_message)
    
    # Access the responsePayload
    response_payload = message_dict.get('responsePayload', {})
    
    # Now you can work with response_payload, for example:
    print(response_payload)
    
    # Format the payload into a readable string
    formatted_payload = "\n".join([f"{key}: {value}" for key, value in response_payload.items()])
    
    # Construct the email subject and body
    email_subject = "Latest Car Prices"
    email_body = f"The latest car prices are:\n\n{formatted_payload}"
    print(email_body)
    
    # Publish the formatted message to the DYNAMIC SNS topic
    response = sns.publish(
        TopicArn=topic_arn,
        Subject=email_subject,
        Message=email_body
    )
    
    # For debugging purposes
    print("Email sent! Message ID:", response['MessageId'])

    return {
        'statusCode': 200,
        'body': json.dumps('Email sent successfully!')
    }