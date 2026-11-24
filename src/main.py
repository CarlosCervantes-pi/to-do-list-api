import os
import json
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import List

import boto3
import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

APP_VERSION = os.getenv("APP_VERSION", "v1.0.0")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
SECRET_NAME = os.getenv("DB_SECRET_NAME", "todo-rds-secret")
CLOUDWATCH_NAMESPACE = "ToDoListApp"

cloudwatch = boto3.client("cloudwatch", region_name=AWS_REGION)
secrets_client = boto3.client("secretsmanager", region_name=AWS_REGION)


def put_custom_metric(metric_name: str, value: float, unit: str = "Count"):
    try:
        cloudwatch.put_metric_data(
            Namespace=CLOUDWATCH_NAMESPACE,
            MetricData=[
                {
                    "MetricName": metric_name,
                    "Value": value,
                    "Unit": unit,
                    "Timestamp": datetime.now(timezone.utc),
                }
            ],
        )
    except Exception:
        pass


def get_db_credentials() -> dict:
    if os.getenv("TESTING") == "1":
        return {}
    response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
    return json.loads(response["SecretString"])


def get_db_connection():
    creds = get_db_credentials()
    return psycopg2.connect(
        host=creds["host"],
        port=creds.get("port", 5432),
        dbname=creds["dbname"],
        user=creds["username"],
        password=creds["password"],
        connect_timeout=5,
    )


def init_db():
    if os.getenv("TESTING") == "1":
        return
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    done BOOLEAN DEFAULT FALSE
                );
                """
            )
        conn.commit()
        conn.close()
    except Exception:
        put_custom_metric("DBConnectionErrors", 1.0)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="To-Do List API", lifespan=lifespan)


class TaskCreate(BaseModel):
    title: str
    done: bool = False


class TaskResponse(BaseModel):
    id: int
    title: str
    done: bool


@app.get("/version")
def get_version():
    return {"version": APP_VERSION}


@app.get("/health")
def get_health():
    timestamp = datetime.now(timezone.utc).isoformat()
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
        conn.close()
        return {"status": "OK", "version": APP_VERSION, "timestamp": timestamp}
    except Exception as e:
        put_custom_metric("DBConnectionErrors", 1.0)
        raise HTTPException(
            status_code=503,
            detail={
                "status": "FAIL",
                "version": APP_VERSION,
                "timestamp": timestamp,
                "error": str(e),
            },
        )


@app.get("/tasks", response_model=List[TaskResponse])
def list_tasks():
    start = time.time()
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id, title, done FROM tasks ORDER BY id ASC;")
            rows = cur.fetchall()
        conn.close()
        latency_ms = (time.time() - start) * 1000
        put_custom_metric("TaskOperationLatency", latency_ms, "Milliseconds")
        return rows
    except Exception as e:
        put_custom_metric("DBConnectionErrors", 1.0)
        raise HTTPException(status_code=500, detail=f"Error al leer tareas: {str(e)}")


@app.post("/tasks", response_model=TaskResponse, status_code=201)
def create_task(task: TaskCreate):
    start = time.time()
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO tasks (title, done) VALUES (%s, %s) RETURNING id, title, done;",
                (task.title, task.done),
            )
            new_task = cur.fetchone()
        conn.commit()
        conn.close()
        latency_ms = (time.time() - start) * 1000
        put_custom_metric("TaskOperationLatency", latency_ms, "Milliseconds")
        return new_task
    except Exception as e:
        put_custom_metric("DBConnectionErrors", 1.0)
        raise HTTPException(status_code=500, detail=f"Error al crear tarea: {str(e)}")
