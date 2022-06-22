# frozen_string_literal: true

module MOS6502
  ##
  # Virtual machine
  class VM
    MEMORY_SIZE = 65_536
    ENTRY_ADDRESS = 0x200
    STACK_ADDRESS = 0x1ff
    PAGE_SIZE = 256
    VECTOR_NMI = 0xfffa
    VECTOR_RESET = 0xfffc
    VECTOR_IRQ = 0xfffe

    OPCODES = {
      opcode_adc: [0x69, 0x65, 0x75, 0x6d, 0x7d, 0x79, 0x61, 0x71],
      opcode_and: [0x29, 0x25, 0x35, 0x2d, 0x3d, 0x39, 0x21, 0x31],
      opcode_asl: [0x0a, 0x06, 0x16, 0x0e, 0x1e],
      opcode_bit: [0x24, 0x2c],
      opcode_bpl: [0x10],
      opcode_bmi: [0x30],
      opcode_bvc: [0x50],
      opcode_bvs: [0x70],
      opcode_bcc: [0x90],
      opcode_bcs: [0xb0],
      opcode_bne: [0xd0],
      opcode_beq: [0xf0],
      opcode_nop: [0xea]
    }.freeze

    ADDRESS_MODES = {
      operand_impl: [0xea],
      operand_imm: [0x69, 0x29],
      operand_acc: [0x0a],
      operand_zp: [0x65, 0x25, 0x06, 0x24],
      operand_zpx: [0x75, 0x35, 0x16],
      operand_abs: [0x6d, 0x2d, 0x0e, 0x2c],
      operand_absx: [0x7d, 0x3d, 0x1e],
      operand_absy: [0x79, 0x39],
      operand_indx: [0x61, 0x21],
      operand_indy: [0x71, 0x31],
      operand_rel: [0x10, 0x30, 0x50, 0x70, 0x90, 0xb0, 0xd0, 0xf0]
    }.freeze

    TIMINGS = [
      [0x69, 2, 0], [0x65, 3, 0], [0x75, 4, 0], [0x6d, 4, 0], [0x7d, 4, 1],
      [0x79, 4, 1], [0x61, 6, 0], [0x71, 5, 1],
      [0x29, 2, 0], [0x25, 3, 0], [0x35, 4, 0], [0x2d, 4, 0], [0x3d, 4, 1],
      [0x39, 4, 1], [0x21, 6, 0], [0x31, 5, 1],
      [0x0a, 2, 0], [0x06, 5, 0], [0x16, 6, 0], [0x0e, 6, 0], [0x1e, 7, 0],
      [0x24, 3, 0], [0x2c, 4, 0],
      [0x10, 1, 1], [0x30, 1, 1], [0x50, 1, 1], [0x70, 1, 1], [0x90, 1, 1],
      [0xb0, 1, 1], [0xd0, 1, 1], [0xf0, 1, 1],
      [0xea, 2, 0]
    ].freeze

    attr_reader :memory, :ra, :rx, :ry, :sp, :pc, :flags, :cycles,
                :entry_address

    def initialize(entry_address: ENTRY_ADDRESS)
      raise VMError, 'Entry address is out of memory band' if entry_address > MEMORY_SIZE

      @entry_address = entry_address
      reset
    end

    def reset
      @memory = Array.new(MEMORY_SIZE, 0)
      @ra = @rx = @ry = 0
      @sp = STACK_ADDRESS
      @pc = @entry_address
      @flags = 0
      @cycles = 0
    end

    def stop
      @running = false
    end

    def run
      @running = true
      step while @running
    end

    def step
      @opcode = @memory[@pc]
      @opcode_address = @pc
      opcode = OPCODES.detect { |_, v| v.include?(@opcode) }
      raise VMError, "Illegal opcode 0x#{@opcode.to_s(16)} at address 0x#{@opcode_address.to_s(16)}" unless opcode

      @pc = (@pc + 1) % MEMORY_SIZE
      @operand = read_operand

      timing = TIMINGS.detect { |t| t[0] == @opcode }
      unless timing
        raise VMError, "Illegal timing with opcode 0x#{@opcode.to_s(16)} at address 0x#{@opcode_address.to_s(16)}"
      end

      @cycles += timing[1]
      @cycles += timing[2] if @page_boundary

      send(opcode.first)
    end

    def load_memory(data, offset: @entry_address)
      raise LoadError, "Data size is too large (#{data.bytesize})" if data.bytesize + offset > MEMORY_SIZE

      data.each_byte.with_index do |byte, i|
        @memory[offset + i] = byte
      end
    end

    private

    def page_boundary?(n)
      (@pc % PAGE_SIZE) + n >= PAGE_SIZE
    end

    ##
    # Flag Carry
    def flag_carry(flag = nil)
      return @flags & 0x1 unless flag

      @flags &= ~1
      @flags |= flag
    end

    ##
    # Flag Zero
    def flag_zero(value = nil)
      return (@flags >> 1) & 0x1 unless value

      @flags &= ~(1 << 1)
      flag = value.zero? ? 1 : 0
      @flags |= flag << 1
    end

    ##
    # Flag Overflow
    def flag_overflow(value = nil)
      return (@flags >> 6) & 0x1 unless value

      @flags &= ~(1 << 6)
      flag = (value >> 6) & 0x1
      @flags |= flag << 6
    end

    ##
    # Flag Negative
    def flag_negative(value = nil)
      return (@flags >> 7) & 0x1 unless value

      @flags &= ~(1 << 7)
      flag = (value >> 7) & 0x1
      @flags |= flag << 7
    end

    def read_operand
      mode = ADDRESS_MODES.detect { |_, v| v.include?(@opcode) }
      unless mode
        raise VMError, "Illegal addressing mode 0x#{@opcode.to_s(16)} at address 0x#{@opcode_address.to_s(16)}"
      end

      send(mode.first)
    end

    ##
    # Implied
    def operand_impl
      @page_boundary = false
    end

    ##
    # Immediate
    def operand_imm
      operand = @memory[@pc]
      @page_boundary = page_boundary?(1)
      @pc = (@pc + 1) % MEMORY_SIZE
      operand
    end

    ##
    # Accumulator
    def operand_acc
      @page_boundary = false
      @ra
    end

    ##
    # Zero page
    def operand_zp
      operand = @memory[@memory[@pc]]
      @page_boundary = page_boundary?(1)
      @pc = (@pc + 1) % MEMORY_SIZE
      operand
    end

    ##
    # Zero page X-indexed
    def operand_zpx
      operand = @memory[(@memory[@pc] + @rx)]
      @page_boundary = page_boundary?(1)
      @pc = (@pc + 1) % MEMORY_SIZE
      operand
    end

    ##
    # Absolute
    def operand_abs
      address = (@memory[@pc] << 8) + @memory[@pc + 1]
      operand = @memory[address]
      @page_boundary = page_boundary?(2)
      @pc = (@pc + 2) % MEMORY_SIZE
      operand
    end

    ##
    # Absolute X-indexed
    def operand_absx
      address = (@memory[@pc] << 8) + @memory[@pc + 1] + @rx
      operand = @memory[address]
      @page_boundary = page_boundary?(2)
      @pc = (@pc + 2) % MEMORY_SIZE
      operand
    end

    ##
    # Absolute Y-indexed
    def operand_absy
      address = (@memory[@pc] << 8) + @memory[@pc + 1] + @ry
      operand = @memory[address]
      @page_boundary = page_boundary?(2)
      @pc = (@pc + 2) % MEMORY_SIZE
      operand
    end

    ##
    # Indirect X-indexed
    def operand_indx
      address = (@memory[@memory[@pc + @rx]] << 8) + @memory[@memory[@pc + @rx + 1]]
      operand = (@memory[address] + @rx) & 0xff
      @page_boundary = page_boundary?(1)
      @pc = (@pc + 1) % MEMORY_SIZE
      operand
    end

    ##
    # Indirect Y-indexed
    def operand_indy
      address = (@memory[@memory[@pc]] << 8) + @memory[@memory[@pc + 1]]
      operand = (@memory[address, 1] + @ry) & 0xff
      @page_boundary = page_boundary?(1)
      @pc = (@pc + 1) % MEMORY_SIZE
      operand
    end

    ##
    # Relative
    def operand_rel
      operand = @memory[@pc]
      @pc = (@pc + 1) % MEMORY_SIZE
      operand
    end

    ##
    # ADC
    def opcode_adc
      ra = @ra + @operand + flag_carry
      @ra = ra & 0xff
      flag_zero(@ra)
      flag_negative(@ra)
      if ra > 0xff
        flag_carry(1)
      else
        flag_carry(0)
      end
    end

    ##
    # AND
    def opcode_and
      @ra &= @operand
      flag_zero(@ra)
      flag_negative(@ra)
    end

    ##
    # ASL
    def opcode_asl
      flag_carry(@ra & 0x1)
      flag_zero(@ra)
      flag_negative(@ra)
      @ra = (@ra << 1) & 0xff
    end

    ##
    # BIT
    def opcode_bit
      flag_zero(@ra & @operand)
      flag_negative(@operand)
      flag_overflow(@operand)
    end

    ##
    # NOP
    def opcode_nop; end
  end

  ##
  # Virtual machine error
  class VMError < StandardError; end

  ##
  # Load error
  class LoadError < StandardError; end
end
