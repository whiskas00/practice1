-- =====================================================================
-- BRONZE, batch 2: «грязная» догрузка.
-- Данные tpch идеально чистые, поэтому проверкам Silver нечего было бы ловить.
-- Я специально дописала (append, как и положено в Bronze) партию с типичными
-- проблемами реальных источников. Silver должен всё это вычистить так,
-- чтобы Gold совпал с эталонным Q16.
-- =====================================================================
SET SESSION bronze.compression_codec = 'ZSTD';

-- ---------- part ----------
-- (а) 200 повторов уже существующих деталей: те же ключи, но brand с пробелами
--     по краям и type в нижнем регистре (как будто другая система выгрузила)
INSERT INTO bronze.lakehouse.part
SELECT partkey, name, mfgr, '  ' || brand || ' ', lower(type), size, container,
       retailprice, comment, 2, 'dirty_feed.part', current_timestamp
FROM bronze.lakehouse.part
WHERE _batch_id = 1 AND partkey <= 200;

-- (б) 20 строк без ключа
INSERT INTO bronze.lakehouse.part
SELECT NULL, name, mfgr, brand, type, size, container,
       retailprice, comment, 2, 'dirty_feed.part', current_timestamp
FROM bronze.lakehouse.part
WHERE _batch_id = 1 AND partkey BETWEEN 1001 AND 1020;

-- (в) 30 новых деталей с недопустимым size (по спецификации TPC-H size от 1 до 50)
INSERT INTO bronze.lakehouse.part
SELECT 2000000 + partkey, name, mfgr, brand, type,
       CASE WHEN partkey % 3 = 0 THEN 0 WHEN partkey % 3 = 1 THEN -5 ELSE 77 END,
       container, retailprice, comment, 2, 'dirty_feed.part', current_timestamp
FROM bronze.lakehouse.part
WHERE _batch_id = 1 AND partkey BETWEEN 1 AND 30;

-- (г) 10 новых деталей без бренда
INSERT INTO bronze.lakehouse.part
SELECT 2000000 + partkey, name, mfgr, NULL, type, size,
       container, retailprice, comment, 2, 'dirty_feed.part', current_timestamp
FROM bronze.lakehouse.part
WHERE _batch_id = 1 AND partkey BETWEEN 31 AND 40;

-- ---------- partsupp ----------
-- (а) 500 точных дублей существующих поставок
INSERT INTO bronze.lakehouse.partsupp
SELECT partkey, suppkey, availqty, supplycost, comment, 2, 'dirty_feed.partsupp', current_timestamp
FROM bronze.lakehouse.partsupp
WHERE _batch_id = 1 AND partkey <= 125;

-- (б) 40 «сирот»: ссылки на детали, которых нет (20 шт.) и на забракованные детали из (в)/(г) (20 шт.)
INSERT INTO bronze.lakehouse.partsupp
SELECT 3000000 + partkey, suppkey, availqty, supplycost, comment, 2, 'dirty_feed.partsupp', current_timestamp
FROM bronze.lakehouse.partsupp
WHERE _batch_id = 1 AND partkey BETWEEN 1 AND 5;
INSERT INTO bronze.lakehouse.partsupp
SELECT 2000000 + partkey, suppkey, availqty, supplycost, comment, 2, 'dirty_feed.partsupp', current_timestamp
FROM bronze.lakehouse.partsupp
WHERE _batch_id = 1 AND partkey BETWEEN 26 AND 30;
-- (в) 20 строк со ссылкой на несуществующего поставщика
INSERT INTO bronze.lakehouse.partsupp
SELECT partkey, 900000 + suppkey % 1000, availqty, supplycost, comment, 2, 'dirty_feed.partsupp', current_timestamp
FROM bronze.lakehouse.partsupp
WHERE _batch_id = 1 AND partkey BETWEEN 501 AND 505;

-- (г) 4 строки с отрицательным остатком / без цены (новые пары ключей, чтобы не путать с дублями)
INSERT INTO bronze.lakehouse.partsupp
SELECT partkey, suppkey + 7, -availqty, CASE WHEN partkey % 2 = 0 THEN NULL ELSE supplycost END,
       comment, 2, 'dirty_feed.partsupp', current_timestamp
FROM bronze.lakehouse.partsupp
WHERE _batch_id = 1 AND partkey BETWEEN 601 AND 604 AND suppkey % 4 = 0;

-- ---------- supplier ----------
-- (а) 50 повторов поставщиков с пробелами в имени и телефоне
INSERT INTO bronze.lakehouse.supplier
SELECT suppkey, ' ' || name || '  ', address, nationkey, phone || ' ', acctbal, comment,
       2, 'dirty_feed.supplier', current_timestamp
FROM bronze.lakehouse.supplier
WHERE _batch_id = 1 AND suppkey <= 50;

-- (б) 5 поставщиков без ключа
INSERT INTO bronze.lakehouse.supplier
SELECT NULL, name, address, nationkey, phone, acctbal, comment,
       2, 'dirty_feed.supplier', current_timestamp
FROM bronze.lakehouse.supplier
WHERE _batch_id = 1 AND suppkey BETWEEN 101 AND 105;
