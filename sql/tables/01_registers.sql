-- 32-bit, 16-bit es 8-bit x86 regiszterek es kodjaik / 32-bit, 16-bit and 8-bit x86 registers and codes
CREATE TABLE IF NOT EXISTS x86_registers (
    name VARCHAR(10) PRIMARY KEY,
    reg_code INT NOT NULL,        -- HU: 0..7 regiszter kod / EN: 0..7 register code (e.g. EAX/AX/AL=0, ECX/CX/CL=1)
    size_bytes INT NOT NULL,      -- HU: Meret bajtban / EN: Size in bytes (1, 2, 4)
    category VARCHAR(10) NOT NULL -- HU: Kategoria / EN: Category ('general', 'segment', etc.)
);

INSERT INTO x86_registers (name, reg_code, size_bytes, category) VALUES
-- HU: 32-bit altalanos regiszterek / EN: 32-bit general-purpose registers
('eax', 0, 4, 'general'),
('ecx', 1, 4, 'general'),
('edx', 2, 4, 'general'),
('ebx', 3, 4, 'general'),
('esp', 4, 4, 'general'),
('ebp', 5, 4, 'general'),
('esi', 6, 4, 'general'),
('edi', 7, 4, 'general'),

-- HU: 16-bit regiszterek / EN: 16-bit registers
('ax', 0, 2, 'general'),
('cx', 1, 2, 'general'),
('dx', 2, 2, 'general'),
('bx', 3, 2, 'general'),
('sp', 4, 2, 'general'),
('bp', 5, 2, 'general'),
('si', 6, 2, 'general'),
('di', 7, 2, 'general'),

-- HU: 8-bit alacsony/magas regiszterek / EN: 8-bit low/high registers
('al', 0, 1, 'general'),
('cl', 1, 1, 'general'),
('dl', 2, 1, 'general'),
('bl', 3, 1, 'general'),
('ah', 4, 1, 'general'),
('ch', 5, 1, 'general'),
('dh', 6, 1, 'general'),
('bh', 7, 1, 'general')
ON CONFLICT (name) DO UPDATE 
SET reg_code = EXCLUDED.reg_code,
    size_bytes = EXCLUDED.size_bytes,
    category = EXCLUDED.category;
