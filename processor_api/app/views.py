from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
import csv
import os
import logging
import traceback

logger = logging.getLogger(__name__)

DATA_DIR = os.getenv('VOLUME_MOUNT_PATH')

class ProcessTheData(APIView):
    def post(self, request):
        data = request.data
        file_name = data.get('file')
        product = data.get('product')
        file_path = os.path.join(DATA_DIR, file_name)
        try:
            with open(file_path, 'r') as file:
                content = file.read()
                print("🔍 File Content Before Processing:\n", content)  # Debugging line
            with open(file_path, 'r') as file:
                reader = csv.DictReader(file)
                reader.fieldnames = [header.strip() for header in reader.fieldnames]
                print("🔍 Normalized CSV Headers:", reader.fieldnames)  # Debugging line
                total = sum(int(row['amount'].strip()) for row in reader if row['product'].strip() == product.strip())
            return Response(
                {"file": file_name, "sum": total},
                status=status.HTTP_200_OK
            )
        except KeyError as e:
            logger.error(f"🚨 KeyError: Missing column: {str(e)}")
            logger.error(traceback.format_exc())
            return Response(
                {"file": file_name, "error": f"Missing column: {str(e)}"},
                status=status.HTTP_400_BAD_REQUEST
            )
        except Exception as e:
            logger.error(f"Error processing file {file_name}: {str(e)}")
            logger.error(traceback.format_exc())
            return Response(
                {"file": file_name, "error": "An error occurred while processing the file."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )