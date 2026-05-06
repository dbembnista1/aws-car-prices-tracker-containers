import json
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('car_prices')

def lambda_handler(event, context):
    try:
        
        response = table.scan(Limit=1)
        items = response.get('Items', [])
        
        if not items:
            return build_response(200, [])
            
        
        all_columns = list(items[0].keys())
        
        
        columns_to_exclude = ['date']
        
        
        models = [col for col in all_columns if col not in columns_to_exclude]
        models.sort()
        
        return build_response(200, models)
        
    except Exception as e:
        print(f"Error fetching models: {e}")
        return build_response(500, {'error': 'Wystąpił błąd po stronie serwera'})

def build_response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,OPTIONS'
        },
        'body': json.dumps(body)
    }