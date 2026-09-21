# Perfilado de MessyOpsOLTP (2026-09-20)

Hallazgos medidos directamente sobre `messyops-server/MessyOpsOLTP` desde el editor de consultas. Son la base de las reglas de limpieza de la capa Silver.

## Inventario

16 tablas de negocio en `dbo`, 15 con CDC habilitado (`data_quality_log` no lo tiene). El CDC está activo a nivel de base (16 instancias de captura en `cdc.change_tables`).

| Tabla | Filas | Columnas |
|---|---|---|
| customers | 4.081 | 12 |
| products | 1.200 | 16 |
| suppliers | 250 | 8 |
| warehouses | 6 | 5 |
| sales_orders | 75.081 | 12 |
| sales_order_lines | 142.502 | 10 |
| invoices | 72.800 | 12 |
| payments | 76.343 | 6 |
| shipments | 72.784 | 8 |
| returns | 5.275 | 9 |
| purchase_orders | 5.296 | 10 |
| purchase_order_lines | 5.420 | 8 |
| supplier_invoices | 4.959 | 9 |
| supplier_payments | 4.873 | 5 |
| inventory_snapshots | 161.408 | 9 |
| support_tickets | 7.323 | 12 |
| data_quality_log | 8.079 | 12 |

Todas las claves son `nvarchar(50)` con prefijo (`CUST-`, `PROD-`, `INV-`…). Las FK existen y están confiadas (`is_not_trusted = 0`). Rango temporal: 2024-01-01 a 2025-12-30.

## Defectos presentes y regla de reparación validada

| Defecto | Filas | Regla en Silver | Validación |
|---|---|---|---|
| `invoices.invoice_date` NULL (fecha mal formada) | 717 | `DATEADD(day, -payment_term_days, due_date)` | 72.083 / 72.083 filas limpias cumplen la regla |
| `sales_orders.order_date` NULL | 233 | fecha de factura del pedido; si no hay, primera fecha de envío | 226 tienen factura con fecha |
| `order_date > ship_date` (día/mes invertidos) | 183 | intercambiar día/mes si resuelve; si no, fecha de factura | el intercambio corrige 77 |
| `sales_order_lines.quantity` NULL (valor imposible) | 291 | `ROUND(line_subtotal / unit_price, 0)` | 142.211 / 142.211 filas limpias |
| `sales_order_lines.discount_rate` NULL | 2.897 | `discount_amount / line_subtotal` | 139.605 / 139.605 filas limpias |
| `purchase_order_lines.unit_cost` error de magnitud | 20 | `line_total / quantity_ordered` cuando no cuadra | los 20 coinciden con el costo del producto |
| `payments` duplicados (`PAY-05…`) | 304 | desduplicar por factura + fecha + importe | los 304 tienen original idéntico |
| `supplier_payments` duplicados (`SPAY-05…`) | 19 | igual que pagos | los 19 tienen original |
| `customers` duplicados (`CUST-0040xx`) | 80 | desduplicar por atributos normalizados | ningún pedido, factura ni ticket los referencia |
| `returns.returned_quantity` > vendido | 6 | acotar a la cantidad vendida | — |
| Texto con espacios / mayúsculas | 52 clientes, 22 productos, 6 proveedores | `TRIM` + normalización de mayúsculas | — |
| `customers.contact_phone` NULL | 221 | se mantiene NULL (no imputable) | — |
| `products.weight_kg` NULL | 43 | se mantiene NULL (no imputable) | — |

## Etiquetas por conformar

| Columna | Variantes | Valor conformado |
|---|---|---|
| customers.country / suppliers.country | US, USA, U.S.A. | United States |
| customers.country | UK, U.K., England | United Kingdom |
| products.category | Electronics Accessory, electronics accessories | Electronics Accessories |

Valores atípicos de una sola fila (probablemente registros de prueba): `customer_segment = Retail`, `region_type = Costa`, `country = Peru`. Se conservan y se reportan en el log de calidad.

## Dominios válidos (para tests `accepted_values`)

- order_status: Completed, Cancelled, Pending Fulfillment
- sales_channel: Online Portal, Phone/Email, Account Manager
- invoice_status: Paid, Overdue, Unpaid, Partially Paid
- payment_method: ACH/Bank Transfer, Wire Transfer, Credit Card, Check
- carrier: Regional Carrier, UPS, FedEx, DHL
- shipping_status: Delivered, In Transit, Lost, Delayed
- po_status: Received, Cancelled, In Transit
- return_reason: Not as Described, Changed Mind, Defective, Damaged in Transit, Wrong Item Shipped
- return_condition: Damaged/Not Resellable, Resellable
- ticket category: Shipping Delay, Product Defect, General Inquiry, Billing Question
- ticket priority: Low, Medium, High, Urgent
- ticket sentiment: Negative, Neutral, Positive
- ticket status: Open, Resolved, Closed
- supplier tier: Reliable, Average, Unreliable
