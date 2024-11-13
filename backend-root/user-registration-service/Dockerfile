# Base image
FROM python:3.8-slim

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy application code
COPY . .

# Expose port and run application
EXPOSE 5000
CMD ["python", "app.py"]

