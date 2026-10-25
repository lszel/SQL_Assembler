-- HU: Leforditott binaris outputok es metaadatok tarolasa / EN: Storage of compiled binary outputs and metadata
CREATE TABLE IF NOT EXISTS build_outputs (
    id SERIAL PRIMARY KEY,
    program_name VARCHAR(100),
    source_code TEXT NOT NULL,
    binary_output BYTEA NOT NULL,
    byte_count INT NOT NULL,
    export_path TEXT,
    compiled_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
