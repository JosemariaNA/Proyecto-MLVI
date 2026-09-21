SELECT
    t.name AS tabla,
    c.name AS columna,
    ty.name AS tipo_dato
FROM sys.tables t
INNER JOIN sys.index_columns ic
    ON t.object_id = ic.object_id
INNER JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id
INNER JOIN sys.indexes i
    ON ic.object_id = i.object_id
    AND ic.index_id = i.index_id
INNER JOIN sys.types ty
    ON c.user_type_id = ty.user_type_id
WHERE i.is_primary_key = 1
ORDER BY t.name;