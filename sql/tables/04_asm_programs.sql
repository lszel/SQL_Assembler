-- HU: Assembly forraskodok programonkent es soronkent torteno tarolasa / EN: Line-by-line storage of assembly source code by program
CREATE TABLE IF NOT EXISTS asm_programs (
    name VARCHAR(100) PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS asm_program_lines (
    program_name VARCHAR(100) REFERENCES asm_programs(name) ON DELETE CASCADE,
    line_number INT NOT NULL,
    line_code TEXT NOT NULL,
    PRIMARY KEY (program_name, line_number)
);
