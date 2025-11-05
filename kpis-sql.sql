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