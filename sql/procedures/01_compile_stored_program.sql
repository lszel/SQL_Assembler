-- HU: Tablaban soronkent tarolt assembly program osszefuzese a futtatoval (runtime), leforditasa es exportalasa
-- EN: Assemble line-by-line program from table with runtime header/footer, compile and export
CREATE OR REPLACE PROCEDURE compile_stored_program(
    IN p_program_name text,
    IN p_filename text DEFAULT NULL,
    IN p_runtime_name text DEFAULT 'linux_elf32',
    IN p_target_dir text DEFAULT '/home/asmtest',
    INOUT p_binary bytea DEFAULT NULL,
    INOUT p_full_path text DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_source text;
    v_combined_source text;
    v_line_count int;
    v_runtime asm_runtimes%ROWTYPE;
    v_raw_code bytea;
    v_target_file text;
    v_byte_count int;
BEGIN
    -- 1. HU: Forraskod osszegyujtese a tablabol / EN: Aggregate source lines from table
    SELECT string_agg(line_code, E'\n' ORDER BY line_number), count(*)
    INTO v_user_source, v_line_count
    FROM asm_program_lines
    WHERE program_name = p_program_name;

    IF v_line_count IS NULL OR v_line_count = 0 THEN
        RAISE EXCEPTION 'A megadott program nem talalhato / Program not found: %', p_program_name;
    END IF;

    -- 2. HU: Kivalasztott futtato (runtime) beolvasasa / EN: Load selected runtime template
    SELECT * INTO v_runtime FROM asm_runtimes WHERE name = p_runtime_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'A megadott runtime nem talalhato / Runtime not found: %', p_runtime_name;
    END IF;

    -- 3. HU: Futtato fejlec + Forraskod + Lablec osszefuzese / EN: Combine runtime header + user source + footer
    v_combined_source := coalesce(v_runtime.prefix_code, '') 
                      || E'\n' || v_user_source || E'\n' 
                      || coalesce(v_runtime.suffix_code, '');

    -- 4. HU: Assembly forditas / EN: Assemble code
    v_raw_code := compile_x86(v_combined_source);

    -- 5. HU: Formatumnak megfelelo csomagolas (ELF32 vagy nyers bin) / EN: Package into target format (ELF32 or raw bin)
    IF v_runtime.target_format = 'elf32' THEN
        p_binary := wrap_in_elf32(v_raw_code);
        IF p_filename IS NULL OR trim(p_filename) = '' THEN
            v_target_file := p_program_name; -- HU: Linux futtathato fajlnev / EN: Linux executable name
        ELSE
            v_target_file := p_filename;
        END IF;
    ELSE
        p_binary := v_raw_code;
        IF p_filename IS NULL OR trim(p_filename) = '' THEN
            v_target_file := p_program_name || '.bin';
        ELSE
            v_target_file := p_filename;
        END IF;
    END IF;

    v_byte_count := octet_length(p_binary);
    p_full_path := rtrim(p_target_dir, '/') || '/' || v_target_file;

    -- 6. HU: Exportalas futtathatokent a szerverre / EN: Export with executable permissions to server
    PERFORM export_binary(p_binary, p_full_path, true);

    -- 7. HU: Rogzites a build_outputs tablaban / EN: Record in build_outputs table
    INSERT INTO build_outputs (
        program_name,
        source_code,
        binary_output,
        byte_count,
        export_path
    ) VALUES (
        p_program_name || ' [' || p_runtime_name || ']',
        v_combined_source,
        p_binary,
        v_byte_count,
        p_full_path
    );

    RAISE NOTICE 'Sikeres onallo program forditas / Compiled successfully: % (runtime: %, % bytes) -> %',
        p_program_name, p_runtime_name, v_byte_count, p_full_path;
END;
$$;
