# Proyecto: Automatización de KPIs
## **Contexto:** 

Actualmente el equipo comercial de una empresa financiera 🏦 genera reportes diarios sobre nivel de ventas, ventas diarias, concentración geográfica de ventas y clientes a quienes más se le ha vendido en los últimos 3 meses.

Esta información es consumida por diferentes analistas. Estos ejecutan diariamente un conjunto de querys para obtener la información.

La principal problemática está en que no se cuenta con un histórico de KPIs organizado (una carpeta con todos los archivos de forma histórica); además, se sigue corriendo de forma manual desde BigQuery.

## **Solución**

La solución planteada es crear un proceso en *Cloud Function* con *Cloud Scheduler* que permita generar de forma automática y programada los reportes en una ruta pre definida y a una hora específica.

## Arquitectura Cloud



---
***Nota:** Es un caso simulado, la información es dummy. Se busca demostrar el uso de Cloud Function principalmente.*

# Obtener fuente de datos
Si quieren obtener la fuente de datos con la que realicé el ejercicio lo pueden obtener desde Kaggle.

## Descargar información

Descargar el **dataset** desde Kaggle.
```powershell
curl -L -o %USERPROFILE%/Downloads/ecommerce-data.zip  https://www.kaggle.com/api/v1/datasets/download/carrie1/ecommerce-data
```

Descomprimir la información
```bash
tar xf "amazon-sales-dataset.zip"
```

## Limpiar y subir información a Bigquery
Prepara la subida de información como dataset principal. Se subirá en GCP.

```Python
!pip install --upgrade google-cloud-bigquery pandas pyarrow

from google.colab import auth
auth.authenticate_user()
print("✅ Autenticado correctamente")
```
Código para procesar y limpiar la información

```Python
import pandas as pd
path = 'data.csv'
dict_names = {'InvoiceNo': 'nro_factura',
              'StockCode': 'codigo_producto',
              'Description': 'descripcion_producto',
              'Quantity': 'cantidad_vendida',
              'InvoiceDate': 'fecha_factura',
              'UnitPrice': 'precio_unitario',
              'CustomerID': 'id_cliente',
              'Country': 'pais_cliente'
              }

data_types = {
    'InvoiceNo': 'string',
    'StockCode': 'string',
    'Description': 'string',
    'Quantity': 'float64',
    'InvoiceDate': 'string',
    'UnitPrice': 'float64',
    'CustomerID': 'string',
    'Country': 'string'
}

df = pd.read_csv(path,
                 delimiter=',',
                 encoding='latin1',
                 dtype=data_types,
                 parse_dates=['InvoiceDate']
                 ).rename(columns=dict_names)

# Quitar la hora
df['fecha_factura_sin_hora'] = df['fecha_factura'].dt.date
# Agregar periodo
df['periodo'] = df['fecha_factura'].dt.strftime('%Y%m')
```

Subir información a BigQuery
```Python
from google.cloud import bigquery

project_id = "proyecto-ventas-diarias"
dataset_id = "ventas"
table_id   = "ventas-diarias"

client = bigquery.Client(project=project_id)
table_ref = f"{project_id}.{dataset_id}.{table_id}"

job = client.load_table_from_dataframe(df, table_ref)
job.result()

print(f"✅ Datos cargados correctamente en {table_ref}")
```

Con esto tendrás disponible la fuente de datos que use.

# Querys para generación de reportería (KPI)
Son querys básicas que nos permitirán obtener la información para construir KPI de ventas básicos.

``` SQL
-- Ventas mensuales (precio unitario * cantidad)
SELECT Periodo, SUM(cantidad_vendida * precio_unitario) as precio_total FROM `proyecto-ventas-diarias.ventas.ventas-diarias`
group by periodo;

-- Ventas diarias acumuladas
SELECT fecha_factura_sin_hora, SUM(cantidad_vendida * precio_unitario) as precio_total FROM `proyecto-ventas-diarias.ventas.ventas-diarias`
group by fecha_factura_sin_hora;

-- Top 3 países con más ventas en el último periodo
SELECT pais_cliente,round(SUM(cantidad_vendida * precio_unitario),2) as precio_total FROM `proyecto-ventas-diarias.ventas.ventas-diarias` 
WHERE Periodo = (SELECT MAX(periodo) FROM `proyecto-ventas-diarias.ventas.ventas-diarias`) and cantidad_vendida > 0
GROUP BY pais_cliente;

-- Cliente con compras superiores a 1000 en el último periodo
WITH CTE_VENTAS_X_CLIENTE AS (
  SELECT periodo,id_cliente, round(SUM(cantidad_vendida * precio_unitario),2) as precio_total FROM `proyecto-ventas-diarias.ventas.ventas-diarias` 
  group by periodo,id_cliente 
) SELECT ID_CLIENTE,ROUND(SUM(PRECIO_TOTAL),2) FROM CTE_VENTAS_X_CLIENTE
WHERE PERIODO = (SELECT MAX(periodo) FROM `proyecto-ventas-diarias.ventas.ventas-diarias`) and precio_total > 1000
GROUP BY ID_CLIENTE
;
```

---
# Configuración y código
## Configuración Cloud Function

## Código Cloud Function
``` python
import functions_framework
import pandas as pd
from google.cloud import bigquery,storage
from datetime import datetime

@functions_framework.http
def main(request):    
    # Nombre de la tabla SQL
    project_id = "proyecto-ventas-diarias"
    dataset_id = "ventas"
    table_id   = "ventas-diarias"

    # Nombre del bucket
    bucket_name = "ventas-diarias-bucket"
    folder = "reporte-diario-ventas"

    # Crear cliente bigquery y storage
    bq_client = bigquery.Client(project=project_id)
    storage_client = storage.Client()

    query_1 = """
    SELECT Periodo, SUM(cantidad_vendida * precio_unitario) as precio_total FROM `proyecto-ventas-diarias.ventas.ventas-diarias` group by periodo;
    """

    query_2 = """
    SELECT fecha_factura_sin_hora, SUM(cantidad_vendida * precio_unitario) as precio_total FROM `proyecto-ventas-diarias.ventas.ventas-diarias` group by fecha_factura_sin_hora;
    """

    query_3 = """
    SELECT pais_cliente,round(SUM(cantidad_vendida * precio_unitario),2) as precio_total FROM `proyecto-ventas-diarias.ventas.ventas-diarias` WHERE Periodo = (SELECT MAX(periodo) FROM `proyecto-ventas-diarias.ventas.ventas-diarias`) and cantidad_vendida > 0 GROUP BY pais_cliente;
    """

    query_4 = """
    WITH CTE_VENTAS_X_CLIENTE AS (
    SELECT periodo,id_cliente, round(SUM(cantidad_vendida * precio_unitario),2) as precio_total FROM `proyecto-ventas-diarias.ventas.ventas-diarias` 
    group by periodo,id_cliente 
    ) SELECT ID_CLIENTE,ROUND(SUM(PRECIO_TOTAL),2) FROM CTE_VENTAS_X_CLIENTE
    WHERE PERIODO = (SELECT MAX(periodo) FROM `proyecto-ventas-diarias.ventas.ventas-diarias`) and precio_total > 1000
    GROUP BY ID_CLIENTE
    ;
    """

    df = bq_client.query(query_1).to_dataframe()
    df_2 = bq_client.query(query_2).to_dataframe()
    df_3 = bq_client.query(query_3).to_dataframe()
    df_4 = bq_client.query(query_4).to_dataframe()

    dataframes = [df,df_2,df_3,df_4]

    fecha_actual = datetime.now().strftime('%Y%m%d')
    bucket = storage_client.bucket(bucket_name)

    for i,dfx in enumerate(dataframes,start=1):
        file_name = f"REPORTE_{i}_KPI_{fecha_actual}.csv"
        blob = bucket.blob(f"{folder}/{file_name}")
        blob.upload_from_string(dfx.to_csv(index=False, sep=";"), content_type="text/csv")

        print(f"✅ Archivo subido: gs://{bucket_name}/{folder}/{file_name}")
    
    return f"⚠️ Se terminó la carga de los archivos. gs://{bucket_name}/{folder}"
```

## Configuración IAM

## Imágenes del resultado Final


Configuracion de IAM ...
Basada en solicitudes
0 instancias (no es importante una respuesta rapida), asi que puede arrancar en frio?

