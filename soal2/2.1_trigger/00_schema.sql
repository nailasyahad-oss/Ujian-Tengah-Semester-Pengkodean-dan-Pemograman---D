-- =====================================================================
-- SOAL 2 UTS - 00_schema.sql
-- Skema persediaan (perpetual) - DDL PERSIS seperti soal (TIDAK DIUBAH)
-- PostgreSQL 14+
-- =====================================================================

-- Idempoten: bersihkan dulu (urutan terbalik karena ada FK)
DROP TABLE IF EXISTS inventory_transactions CASCADE;
DROP TABLE IF EXISTS inventory_items CASCADE;

-- ---------------------------------------------------------------------
-- DDL ASLI DARI SOAL (persis, tidak diubah)
-- ---------------------------------------------------------------------
CREATE TABLE inventory_items (
  item_id VARCHAR(10) PRIMARY KEY,
  item_name VARCHAR(100),
  stock_qty INT NOT NULL DEFAULT 0,
  unit_cost NUMERIC(15, 2) NOT NULL
);
CREATE TABLE inventory_transactions (
  trx_id SERIAL PRIMARY KEY,
  item_id VARCHAR(10) REFERENCES inventory_items(item_id),
  trx_type VARCHAR(10) CHECK (trx_type IN ('PURCHASE', 'SALE', 'ADJUSTMENT')),
  qty INT NOT NULL,
  trx_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- SEED DATA AWAL
-- BRG001: stok 10, unit_cost 50.000  (dipakai di seluruh skenario uji)
-- BRG002: stok 5,  unit_cost 25.000  (untuk variasi tambahan)
-- ---------------------------------------------------------------------
INSERT INTO inventory_items (item_id, item_name, stock_qty, unit_cost) VALUES
  ('BRG001', 'Barang Uji 001', 10, 50000.00),
  ('BRG002', 'Barang Uji 002',  5, 25000.00);

-- Verifikasi seed
SELECT * FROM inventory_items ORDER BY item_id;
