-- HU: x86 Utasitasok tokenjei es binaris kodjai / EN: x86 Instruction tokens and binary opcodes
CREATE TABLE IF NOT EXISTS x86_instructions (
    id SERIAL PRIMARY KEY,
    mnemonic VARCHAR(20) NOT NULL,
    operands_format VARCHAR(30) NOT NULL, -- HU: pl. '', 'reg32', 'reg32, reg32' / EN: e.g. '', 'reg32', 'reg32, reg32'
    encoding_type VARCHAR(20) NOT NULL,   -- HU: pl. 'fixed', 'reg_plus', 'modrm_rr' / EN: e.g. 'fixed', 'reg_plus', 'modrm_rr'
    base_opcode BYTEA NOT NULL,
    description TEXT,
    CONSTRAINT uq_mnemonic_format UNIQUE (mnemonic, operands_format)
);

INSERT INTO x86_instructions (mnemonic, operands_format, encoding_type, base_opcode, description) VALUES
-- HU: 0 operandusu rogzitett utasitasok / EN: 0-operand fixed instructions
('nop',  '', 'fixed', '\x90'::bytea, 'No operation'),
('ret',  '', 'fixed', '\xc3'::bytea, 'Near return to calling procedure'),
('hlt',  '', 'fixed', '\xf4'::bytea, 'Halt processor'),
('cli',  '', 'fixed', '\xfa'::bytea, 'Clear interrupt flag'),
('sti',  '', 'fixed', '\xfb'::bytea, 'Set interrupt flag'),
('cld',  '', 'fixed', '\xfc'::bytea, 'Clear direction flag'),
('std',  '', 'fixed', '\xfd'::bytea, 'Set direction flag'),
('int3', '', 'fixed', '\xcc'::bytea, 'Trap to debugger'),

-- HU: Megszakitasok / EN: Interrupts
('int', 'imm8', 'imm8', '\xcd'::bytea, 'Call interrupt service routine'),

-- HU: Regiszter kodot tartalmazo utasitasok / EN: Register-coded instructions (opcode = base + reg_code)
('push', 'reg32', 'reg_plus', '\x50'::bytea, 'Push 32-bit register onto stack (0x50 + reg)'),
('pop',  'reg32', 'reg_plus', '\x58'::bytea, 'Pop stack into 32-bit register (0x58 + reg)'),
('inc',  'reg32', 'reg_plus', '\x40'::bytea, 'Increment 32-bit register (0x40 + reg)'),
('dec',  'reg32', 'reg_plus', '\x48'::bytea, 'Decrement 32-bit register (0x48 + reg)'),

-- HU: Konstans betoltes regiszterbe / EN: Load immediate into register
('mov', 'reg32, imm32', 'mov_reg_imm32', '\xb8'::bytea, 'Move 32-bit immediate into register (0xB8 + reg + imm32)'),
('mov', 'reg8, imm8',   'mov_reg_imm8',   '\xb0'::bytea, 'Move 8-bit immediate into register (0xB0 + reg + imm8)'),

-- HU: Ket regiszteres muveletek / EN: Two-register operations (ModR/M byte: 0xC0 | (src << 3) | dst)
('mov', 'reg32, reg32', 'modrm_rr', '\x89'::bytea, 'Move reg2 to reg1 (MOV r/m32, r32)'),
('add', 'reg32, reg32', 'modrm_rr', '\x01'::bytea, 'Add reg2 to reg1'),
('sub', 'reg32, reg32', 'modrm_rr', '\x29'::bytea, 'Subtract reg2 from reg1'),
('xor', 'reg32, reg32', 'modrm_rr', '\x31'::bytea, 'Bitwise XOR reg2 into reg1'),
('and', 'reg32, reg32', 'modrm_rr', '\x21'::bytea, 'Bitwise AND reg2 into reg1'),
('or',  'reg32, reg32', 'modrm_rr', '\x09'::bytea, 'Bitwise OR reg2 into reg1'),
('cmp', 'reg32, reg32', 'modrm_rr', '\x39'::bytea, 'Compare reg1 with reg2'),

-- HU: Ugrasok es eljarashivasok / EN: Jumps and procedure calls
('call', 'rel32', 'call', '\xe8'::bytea, 'Call procedure near (rel32)'),
('jmp',  'rel8',  'rel8', '\xeb'::bytea, 'Short relative jump'),
('jz',  'rel8', 'rel8', '\x74'::bytea, 'Jump if zero / equal'),
('je',  'rel8', 'rel8', '\x74'::bytea, 'Jump if equal'),
('jnz', 'rel8', 'rel8', '\x75'::bytea, 'Jump if not zero / not equal'),
('jne', 'rel8', 'rel8', '\x75'::bytea, 'Jump if not equal'),
('jc',  'rel8', 'rel8', '\x72'::bytea, 'Jump if carry'),
('jnc', 'rel8', 'rel8', '\x73'::bytea, 'Jump if not carry')

ON CONFLICT (mnemonic, operands_format) DO UPDATE
SET encoding_type = EXCLUDED.encoding_type,
    base_opcode = EXCLUDED.base_opcode,
    description = EXCLUDED.description;
