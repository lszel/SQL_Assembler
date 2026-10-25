-- HU: PL/Python3u kiterjesztes biztositasa / EN: Ensure PL/Python3u extension is available
CREATE EXTENSION IF NOT EXISTS plpython3u;

-- HU: Korabbi tultoltes torlese az egyertelmuseg kedveert / EN: Drop obsolete overload for clean interface
DROP FUNCTION IF EXISTS export_binary(bytea, text);

-- HU: Binaris adat (bytea) kimentese a szerver fajlrendszerebe futtathato jogosultsaggal
-- EN: Export binary data (bytea) to server filesystem with executable permissions
CREATE OR REPLACE FUNCTION export_binary(
    p_binary bytea,
    p_filepath text,
    p_make_executable boolean DEFAULT true
)
RETURNS text
LANGUAGE plpython3u
SECURITY DEFINER
AS $$
import os

if p_binary is None:
    plpy.error("A binaris adat ures (NULL)! / Binary data is empty (NULL)!")

dirpath = os.path.dirname(p_filepath)
if dirpath and not os.path.exists(dirpath):
    os.makedirs(dirpath, exist_ok=True)

with open(p_filepath, "wb") as f:
    f.write(p_binary)

if p_make_executable:
    os.chmod(p_filepath, 0o755)

return p_filepath
$$;
