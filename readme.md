# Proyecto: Automatización de KPIs
Contexto: actualmente en una empresa se genera reportería diaria sobre KPIs de ventas (ventas acumuludas ...), como esta información es consumida por varias áreas puede que múltiples analistas la ejecuten a lo largo del día (reproceso) y que no se tenga claro y organizado un histórico.

Con este proyecto se busca automatizar la ejecución y obtención de información de los KPIs (consultas en SQL), dejarlos en un ruta y a una hora definida. Esto permitirá evitar reprocesos y se tendrá un lugar donde revisar el avance diario.

**Nota:** Es un caso hipotético, la información obtenida es dummy. Busco principalmente poner en práctica mis conocimiento sobre.... Sin embargo, la arquitectura planteada aquí se podría llevar a la práctica sin ningún problema.

El objetivo de este pequeño proyecto es consumir información de bases de datos (Big Query) y diariamente colocar esa información en Excels (dashboard) en un ruta.

Con este proyecto espero demostrar mis conocimientos sobre VM, Images, IAM (falta), Bigquery básico, buckets? (almacenamiento), cloud function?

Si quieres replicar mi proceso para obtener la información

# Obtener fuente de datos

## Descargar información

En esta parte enseño como obtener la información de Kaggle, usaré esta información como ejemplo. No es data del caso real.

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
auth.authenticate_user()  # Abre el popup de login
print("✅ Autenticado correctamente")
```
Código para procesar la información

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

Con esto tendrás disponible la fuente de datos que use. No es necesario y de hecho se esperaría que usen las fuentes de datos originales.

# Querys para generación de reportería (KPI)
Son querys de ejemplos de posibles KPIs según la información presente.
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

# Arquitectura en la nube
El objetivo es prender una VM con una image pre-configurada con la versión de python y librerías necesarias para obtener la información de bigquery diariamente.
pasos:
- prender la VM con la imagen
- traer la data y descargarlo en un Excel
- cargar ese excel en un bucket

La otra opción es hacerlo con una cloud function...