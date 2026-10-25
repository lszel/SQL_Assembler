-- HU: Segedfv egesz szamok (decimalis, 0x... es ...h hex) ertelmezesere
-- EN: Helper function to parse integer values (decimal, 0x... and ...h hex)
CREATE OR REPLACE FUNCTION parse_asm_int(p_val text)
RETURNS bigint
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_clean text := lower(trim(p_val));
    v_sign bigint := 1;
BEGIN
    IF v_clean LIKE '-%' THEN
        v_sign := -1;
        v_clean := substring(v_clean from 2);
    ELSIF v_clean LIKE '+%' THEN
        v_clean := substring(v_clean from 2);
    END IF;

    IF v_clean LIKE '0x%' THEN
        RETURN v_sign * ('x' || lpad(substring(v_clean from 3), 16, '0'))::bit(64)::bigint;
    ELSIF v_clean ~ '^[0-9a-f]+h$' THEN
        RETURN v_sign * ('x' || lpad(substring(v_clean from 1 for length(v_clean)-1), 16, '0'))::bit(64)::bigint;
    ELSIF v_clean ~ '^[0-9]+$' THEN
        RETURN v_sign * v_clean::bigint;
    ELSE
        RAISE EXCEPTION 'Ervenytelen numerikus ertek / Invalid numeric value: %', p_val;
    END IF;
END;
$$;

-- HU: x86 Assembler fordito (Forras szoveg -> Bytea gepikod)
-- EN: x86 Assembler compiler (Source text -> Bytea machine code)
CREATE OR REPLACE FUNCTION compile_x86(p_source text)
RETURNS bytea
LANGUAGE plpgsql
AS $$
DECLARE
    v_lines text[];
    v_line text;
    v_clean_line text;
    v_token text;
    v_mnemonic text;
    v_operands_str text;
    v_op1 text;
    v_op2 text;
    v_op_count int;
    
    -- HU: Cimkek tarolasa ketmenetes feldolgozashoz / EN: Label storage for 2-pass assembly
    v_labels jsonb := '{}'::jsonb;
    v_line_len int;
    v_cur_offset int := 0;

    -- HU: Menet vezerles / EN: Pass control
    v_pass int;
    v_final_output bytea := ''::bytea;

    -- HU: Regiszter / Utasitas metaadatok / EN: Register / Instruction metadata
    v_reg1_code int;
    v_reg2_code int;
    v_reg1_size int;
    v_reg2_size int;
    v_inst record;

    -- HU: Szamitasok / EN: Calculations
    v_imm_val bigint;
    v_modrm int;
    v_rel_offset int;
    v_byte_code bytea;
    v_imm_byte int;
BEGIN
    IF p_source IS NULL OR trim(p_source) = '' THEN
        RETURN ''::bytea;
    END IF;

    -- HU: Forraskod felbontasa sorokra / EN: Split source code into lines
    v_lines := regexp_split_to_array(p_source, E'\\r?\\n');

    -- HU: 2 MENETES FORDITAS (Pass 1: cimkek es meretek, Pass 2: kodgeneralas)
    -- EN: 2-PASS COMPILATION (Pass 1: labels and offsets, Pass 2: machine code generation)
    FOR v_pass IN 1..2 LOOP
        v_cur_offset := 0;
        IF v_pass = 2 THEN
            v_final_output := ''::bytea;
        END IF;

        FOREACH v_line IN ARRAY v_lines LOOP
            -- HU: Megjegyzesek (;, //, #) levagasa / EN: Strip comments (;, //, #)
            v_clean_line := trim(regexp_replace(v_line, E'(;|//|#).*$', ''));
            
            IF v_clean_line = '' THEN
                CONTINUE;
            END IF;

            -- HU: Cimkek detektalasa / EN: Detect labels (e.g. "loop_start:")
            IF v_clean_line ~ '^[a-zA-Z_][a-zA-Z0-9_]*:$' THEN
                IF v_pass = 1 THEN
                    v_token := lower(rtrim(v_clean_line, ':'));
                    v_labels := jsonb_set(v_labels, ARRAY[v_token], to_jsonb(v_cur_offset));
                END IF;
                CONTINUE;
            END IF;

            -- HU: Sor felbontasa mnemonikra es operandusokra / EN: Parse line into mnemonic and operands
            v_mnemonic := lower(trim(substring(v_clean_line from E'^([a-zA-Z0-9]+)')));
            v_operands_str := trim(substring(v_clean_line from E'^[a-zA-Z0-9]+\\s*(.*)$'));

            v_op1 := '';
            v_op2 := '';
            v_op_count := 0;

            IF v_operands_str <> '' THEN
                IF position(',' IN v_operands_str) > 0 THEN
                    v_op1 := lower(trim(split_part(v_operands_str, ',', 1)));
                    v_op2 := lower(trim(split_part(v_operands_str, ',', 2)));
                    v_op_count := 2;
                ELSE
                    v_op1 := lower(trim(v_operands_str));
                    v_op_count := 1;
                END IF;
            END IF;

            v_byte_code := ''::bytea;

            -- 1) HU: 0 OPERANDUS / EN: 0 OPERANDS
            IF v_op_count = 0 THEN
                SELECT * INTO v_inst FROM x86_instructions WHERE mnemonic = v_mnemonic AND operands_format = '';
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Ismeretlen 0-operandusu utasitas / Unknown 0-operand instruction: %', v_mnemonic;
                END IF;
                v_byte_code := v_inst.base_opcode;

            -- 2) HU: 1 OPERANDUS / EN: 1 OPERAND
            ELSIF v_op_count = 1 THEN
                -- HU: Regiszter operandus / EN: Register operand (e.g. push eax, pop ebx, inc edx, dec ecx)
                SELECT reg_code, size_bytes INTO v_reg1_code, v_reg1_size FROM x86_registers WHERE name = v_op1;
                IF FOUND AND v_reg1_size = 4 THEN
                    SELECT * INTO v_inst FROM x86_instructions WHERE mnemonic = v_mnemonic AND operands_format = 'reg32';
                    IF FOUND AND v_inst.encoding_type = 'reg_plus' THEN
                        v_byte_code := set_byte(''::bytea || '\x00'::bytea, 0, get_byte(v_inst.base_opcode, 0) + v_reg1_code);
                    ELSE
                        RAISE EXCEPTION 'Nem tamogatott reg32 utasitas / Unsupported reg32 instruction: % %', v_mnemonic, v_op1;
                    END IF;

                -- HU: Megszakitas / EN: Interrupt (int imm8, e.g. int 0x80)
                ELSIF v_mnemonic = 'int' THEN
                    v_imm_val := parse_asm_int(v_op1);
                    IF v_imm_val = 3 THEN
                        v_byte_code := '\xcc'::bytea; -- INT 3
                    ELSE
                        v_byte_code := '\xcd'::bytea || set_byte('\x00'::bytea, 0, (v_imm_val & 255)::int);
                    END IF;

                -- HU: Eljarashivas / EN: Procedure call (call label / call rel32)
                ELSIF v_mnemonic = 'call' THEN
                    IF v_pass = 1 THEN
                        -- HU: 1. menetben 5 bajtot feltetelezunk / EN: In pass 1 assume 5 bytes (E8 + rel32)
                        v_byte_code := '\xe800000000'::bytea;
                    ELSE
                        IF v_labels ? v_op1 THEN
                            v_rel_offset := (v_labels->>v_op1)::int - (v_cur_offset + 5);
                        ELSE
                            v_rel_offset := parse_asm_int(v_op1)::int;
                        END IF;

                        v_byte_code := '\xe8'::bytea
                            || set_byte('\x00'::bytea, 0, (v_rel_offset & 255)::int)
                            || set_byte('\x00'::bytea, 0, ((v_rel_offset >> 8) & 255)::int)
                            || set_byte('\x00'::bytea, 0, ((v_rel_offset >> 16) & 255)::int)
                            || set_byte('\x00'::bytea, 0, ((v_rel_offset >> 24) & 255)::int);
                    END IF;

                -- HU: Ugrasok / EN: Jumps (jmp, jz, jnz, je, jne, jc, jnc)
                ELSIF v_mnemonic IN ('jmp', 'jz', 'je', 'jnz', 'jne', 'jc', 'jnc') THEN
                    SELECT * INTO v_inst FROM x86_instructions WHERE mnemonic = v_mnemonic AND operands_format = 'rel8';
                    IF NOT FOUND THEN
                        RAISE EXCEPTION 'Nem tamogatott ugras / Unsupported jump: %', v_mnemonic;
                    END IF;

                    IF v_pass = 1 THEN
                        -- HU: 1. menetben 2 bajtot feltetelezunk / EN: In pass 1 assume 2 bytes (opcode + rel8)
                        v_byte_code := v_inst.base_opcode || '\x00'::bytea;
                    ELSE
                        -- HU: 2. menet: cimke feloldasa / EN: Pass 2: resolve label
                        IF v_labels ? v_op1 THEN
                            v_rel_offset := (v_labels->>v_op1)::int - (v_cur_offset + 2);
                        ELSE
                            v_rel_offset := parse_asm_int(v_op1)::int;
                        END IF;

                        IF v_rel_offset < -128 OR v_rel_offset > 127 THEN
                            RAISE EXCEPTION 'A relativ ugras tul tavoli a short jump-hoz / Jump target too far for rel8: % (% bytes)', v_op1, v_rel_offset;
                        END IF;

                        -- HU: 2-komplement 8-bit / EN: 2s complement 8-bit
                        v_imm_byte := (v_rel_offset & 255);
                        v_byte_code := v_inst.base_opcode || set_byte('\x00'::bytea, 0, v_imm_byte);
                    END IF;
                ELSE
                    RAISE EXCEPTION 'Ismeretlen 1-operandusu utasitas / Unknown 1-operand instruction: % %', v_mnemonic, v_op1;
                END IF;

            -- 3) HU: 2 OPERANDUS / EN: 2 OPERANDS
            ELSIF v_op_count = 2 THEN
                SELECT reg_code, size_bytes INTO v_reg1_code, v_reg1_size FROM x86_registers WHERE name = v_op1;
                SELECT reg_code, size_bytes INTO v_reg2_code, v_reg2_size FROM x86_registers WHERE name = v_op2;

                -- HU: REG32, REG32 muveletek / EN: REG32, REG32 operations (mov, add, sub, xor, and, or, cmp)
                IF v_reg1_code IS NOT NULL AND v_reg2_code IS NOT NULL AND v_reg1_size = 4 AND v_reg2_size = 4 THEN
                    SELECT * INTO v_inst FROM x86_instructions WHERE mnemonic = v_mnemonic AND operands_format = 'reg32, reg32';
                    IF NOT FOUND THEN
                        RAISE EXCEPTION 'Nem tamogatott reg32, reg32 utasitas / Unsupported reg32, reg32 instruction: %', v_mnemonic;
                    END IF;
                    -- ModR/M byte: 11b | (src << 3) | dst
                    v_modrm := 192 + (v_reg2_code * 8) + v_reg1_code;
                    v_byte_code := v_inst.base_opcode || set_byte('\x00'::bytea, 0, v_modrm);

                -- HU: MOV REG32, IMM32 / EN: MOV REG32, IMM32 (e.g. mov eax, 1)
                ELSIF v_mnemonic = 'mov' AND v_reg1_code IS NOT NULL AND v_reg1_size = 4 THEN
                    v_imm_val := parse_asm_int(v_op2);
                    -- Opcode: 0xB8 + reg_code
                    v_byte_code := set_byte('\x00'::bytea, 0, 184 + v_reg1_code);
                    -- HU: 32-bit Little-Endian konstans / EN: 32-bit Little-Endian immediate
                    v_byte_code := v_byte_code 
                        || set_byte('\x00'::bytea, 0, (v_imm_val & 255)::int)
                        || set_byte('\x00'::bytea, 0, ((v_imm_val >> 8) & 255)::int)
                        || set_byte('\x00'::bytea, 0, ((v_imm_val >> 16) & 255)::int)
                        || set_byte('\x00'::bytea, 0, ((v_imm_val >> 24) & 255)::int);

                -- HU: MOV REG8, IMM8 / EN: MOV REG8, IMM8 (e.g. mov al, 0x05)
                ELSIF v_mnemonic = 'mov' AND v_reg1_code IS NOT NULL AND v_reg1_size = 1 THEN
                    v_imm_val := parse_asm_int(v_op2);
                    -- Opcode: 0xB0 + reg_code
                    v_byte_code := set_byte('\x00'::bytea, 0, 176 + v_reg1_code)
                        || set_byte('\x00'::bytea, 0, (v_imm_val & 255)::int);
                ELSE
                    RAISE EXCEPTION 'Nem tamogatott 2-operandusu kombinacio / Unsupported 2-operand combination: % %, %', v_mnemonic, v_op1, v_op2;
                END IF;
            END IF;

            v_line_len := octet_length(v_byte_code);
            v_cur_offset := v_cur_offset + v_line_len;

            IF v_pass = 2 THEN
                v_final_output := v_final_output || v_byte_code;
            END IF;
        END LOOP;
    END LOOP;

    RETURN v_final_output;
END;
$$;

-- HU: Gepikod becsomagolasa onallo, kozvetlenul futtathato 32-bites Linux ELF binarisba
-- EN: Package raw machine code into standalone, directly executable 32-bit Linux ELF binary
CREATE OR REPLACE FUNCTION wrap_in_elf32(p_code bytea)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_filesz int;
    v_header bytea;
BEGIN
    v_filesz := 84 + octet_length(p_code);

    -- HU: 52 bajtos Elf32_Ehdr fejlec / EN: 52-byte Elf32_Ehdr header
    v_header := '\x7f454c46010101000000000000000000'::bytea  -- e_ident: \x7fELF, 32-bit, little-endian, version 1, sysv
        || '\x0200'::bytea                                      -- e_type: ET_EXEC (2)
        || '\x0300'::bytea                                      -- e_machine: EM_386 (3)
        || '\x01000000'::bytea                                  -- e_version: 1
        || '\x54800408'::bytea                                  -- e_entry: 0x08048054 (vaddr 0x08048000 + 84 bytes)
        || '\x34000000'::bytea                                  -- e_phoff: 52 bytes
        || '\x00000000'::bytea                                  -- e_shoff: 0
        || '\x00000000'::bytea                                  -- e_flags: 0
        || '\x3400'::bytea                                      -- e_ehsize: 52
        || '\x2000'::bytea                                      -- e_phentsize: 32
        || '\x0100'::bytea                                      -- e_phnum: 1
        || '\x0000'::bytea                                      -- e_shentsize: 0
        || '\x0000'::bytea                                      -- e_shnum: 0
        || '\x0000'::bytea                                      -- e_shstrndx: 0
        -- HU: 32 bajtos Elf32_Phdr program fejlec (PT_LOAD) / EN: 32-byte Elf32_Phdr program header (PT_LOAD)
        || '\x01000000'::bytea                                  -- p_type: PT_LOAD (1)
        || '\x00000000'::bytea                                  -- p_offset: 0
        || '\x00800408'::bytea                                  -- p_vaddr: 0x08048000
        || '\x00800408'::bytea                                  -- p_paddr: 0x08048000
        -- HU: p_filesz 4 bajt little-endian / EN: p_filesz 4 bytes little-endian
        || set_byte('\x00'::bytea, 0, (v_filesz & 255)::int)
        || set_byte('\x00'::bytea, 0, ((v_filesz >> 8) & 255)::int)
        || set_byte('\x00'::bytea, 0, ((v_filesz >> 16) & 255)::int)
        || set_byte('\x00'::bytea, 0, ((v_filesz >> 24) & 255)::int)
        -- HU: p_memsz 4 bajt little-endian / EN: p_memsz 4 bytes little-endian
        || set_byte('\x00'::bytea, 0, (v_filesz & 255)::int)
        || set_byte('\x00'::bytea, 0, ((v_filesz >> 8) & 255)::int)
        || set_byte('\x00'::bytea, 0, ((v_filesz >> 16) & 255)::int)
        || set_byte('\x00'::bytea, 0, ((v_filesz >> 24) & 255)::int)
        || '\x07000000'::bytea                                  -- p_flags: PF_R | PF_W | PF_X (7)
        || '\x00100000'::bytea;                                 -- p_align: 4096 (0x1000)

    RETURN v_header || p_code;
END;
$$;

