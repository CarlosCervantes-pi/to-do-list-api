# To-Do List API (CI/CD + Observabilidad)

API REST en FastAPI conectada a Amazon RDS (PostgreSQL), con credenciales gestionadas en AWS Secrets Manager, infraestructura aprovisionada mediante Terraform, despliegue automatizado con GitHub Actions y monitoreo en Amazon CloudWatch.

## Endpoints

- `GET /tasks`: Lista todas las tareas almacenadas en RDS.
- `POST /tasks`: Crea una tarea nueva (`{"title": "texto", "done": false}`).
- `GET /version`: Muestra la versión actual desplegada.
- `GET /health`: Verifica la conexión con RDS y devuelve el estado, versión y timestamp.

## Ejecución Local

```bash
python -m venv venv
venv\Scripts\activate
pip install -r src/requirements.txt
pytest -v
```

## Secretos requeridos en GitHub Actions

Configurar en **Settings > Secrets and variables > Actions**:
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
- `TF_STATE_BUCKET`: Nombre del bucket S3 para guardar el archivo `terraform.tfstate`.
- `EC2_PUBLIC_KEY` y `EC2_PRIVATE_KEY`: Par de llaves SSH (`ssh-keygen -t rsa -b 4096`).
- `DB_PASSWORD`: Contraseña para la base de datos PostgreSQL.
- `ALERT_EMAIL`: Correo para recibir alertas de SNS.

## Crear y Destruir Infraestructura

1. **Crear**: Ir a la pestaña **Actions** en GitHub, seleccionar **Provisionar Infraestructura (Terraform)** y ejecutar **Run workflow**.
2. **Desplegar nueva versión**: Crear y subir un tag con formato `v#.#.#`:
   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```
3. **Destruir**: Ir a **Actions**, seleccionar **Destruir Infraestructura (Terraform)** y ejecutar **Run workflow**.

Verificacion de pruebas unitarias.
