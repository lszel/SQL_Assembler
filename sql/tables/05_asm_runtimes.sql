-- HU: Futtatok (runtime shimek es headerek) kulon tarolasa / EN: Storage of standalone runtimes, headers, and footers
CREATE TABLE IF NOT EXISTS asm_runtimes (
    name VARCHAR(50) PRIMARY KEY,
    description TEXT,
    prefix_code TEXT NOT NULL,
    suffix_code TEXT NOT NULL,
    target_format VARCHAR(20) NOT NULL DEFAULT 'elf32' -- HU: 'elf32' (onallo) vagy 'bin' (nyers) / EN: 'elf32' (standalone) or 'bin' (raw)
);

INSERT INTO asm_runtimes (name, description, prefix_code, suffix_code, target_format) VALUES
(
    'linux_elf32',
    'HU: Kozvetlenul futtathato 32-bites Linux ELF binaris (EAX -> exit code). / EN: Standalone 32-bit Linux ELF executable passing EAX return value as exit code.',
    E'; --- STANDALONE LINUX RUNNER HEADER ---\ncall user_main\nmov ebx, eax    ; Exit code = EAX\nmov eax, 1      ; Linux sys_exit syscall (eax=1)\nint 0x80        ; Linux kernel interrupt\nuser_main:\n',
    E'\n; --- STANDALONE LINUX RUNNER FOOTER ---\nret\n',
    'elf32'
),
(
    'raw',
    'HU: Nyers gepikod futtato fejlec es lablec nelkul. / EN: Raw machine code without header/footer.',
    '',
    '',
    'bin'
)
ON CONFLICT (name) DO UPDATE
SET description   = EXCLUDED.description,
    prefix_code   = EXCLUDED.prefix_code,
    suffix_code   = EXCLUDED.suffix_code,
    target_format = EXCLUDED.target_format;
