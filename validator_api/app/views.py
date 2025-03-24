import os
import csv
import requests
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response

PROCESSOR_API_BASE_URL = os.getenv('PROCESSOR_API_BASE_URL')
PROCESSOR_API_URL = f"{PROCESSOR_API_BASE_URL}/process"
DATA_DIR = os.getenv('VOLUME_MOUNT_PATH')

class StoreFile(APIView):
    def post(self, request):
        data = request.data
        file_name = data.get('file')
        file_content = data.get('data')
        if not file_name or not file_content:
            return Response(
                {"file": None, "error": "Invalid JSON input."},
                status=status.HTTP_400_BAD_REQUEST
            )
        file_path = os.path.join(DATA_DIR, file_name)
        try:
            with open(file_path, 'w') as f:
                f.write(file_content)
            return Response(
                {"file": file_name, "message": "Success."},
                status=status.HTTP_201_CREATED
            )
        except Exception as e:
            return Response(
                {"file": file_name, "error": "Error while storing the file to the storage."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

class Calculate(APIView):
    def post(self, request):
        data = request.data
        file_name = data.get('file')
        product = data.get('product')
        if not file_name or not product:
            return Response(
                {"file": None, "error": "Invalid JSON input."},
                status=status.HTTP_400_BAD_REQUEST
            )
        file_path = os.path.join(DATA_DIR, file_name)
        if not os.path.isfile(file_path):
            return Response(
                {"file": file_name, "error": "File not found."},
                status=status.HTTP_404_NOT_FOUND
            )
        try:
            with open(file_path, 'r') as csvfile:
                reader = csv.DictReader(csvfile)
                reader.fieldnames = [header.strip() for header in reader.fieldnames]
                print("Headers:", reader.fieldnames)
                for row in reader:
                    print(row)
                expected_headers = ['product', 'amount']
                if not all(header in reader.fieldnames for header in expected_headers):
                    return Response(
                        {"file": file_name, "error": "Input file not in CSV format."},
                        status=status.HTTP_400_BAD_REQUEST
                    )
        except Exception:
            return Response(
                {"file": file_name, "error": "Error while reading the file."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
        try:
            response = requests.post(PROCESSOR_API_URL, json=data)
            return Response(response.json(), status=response.status_code)
        except requests.exceptions.RequestException:
            return Response(
                {"error": "Unable to connect to Processor API."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )