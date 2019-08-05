class E65
  FREQUENCY = 1000000
  MEMORY_SIZE = 65536
  PAGE_SIZE = 256
  NMI_ADDRESS = 0xfffa
  RESET_ADDRESS = 0xfffc
  IRQ_ADDRESS = 0xfffe
  
  def initialize
    @running = false
    init
    reset
  end

  def init
    @mem = Array.new(MEMORY_SIZE, 0x00)
    @pc = 0x00
    @reg = {
      :a => 0x00,
      :x => 0x00,
      :y => 0x00,
      :p => 0b00100000, # [NV1BDIZC]
      :s => 0x00,
    }
  end
  
  def reset(cold = true)
    init if cold
    @pc = read_word(RESET_ADDRESS)
  end

  def read_word(address)
    (@mem[address + 1] << 8) + @mem[address]
  end

  def signed_int(int)
    i = int & 0b01111111
    i * -1 if int >= 128
    return i
  end

  def flag_c?
    @reg["p"] & 0b00000001 == 1
  end

  def flag_z?
    (@reg["p"] & 0b00000010) >> 1 == 1
  end

  def flag_n?
    (@reg["p"] & 0b10000000) >> 7 == 1
  end
  
  def page_boundary?
    @pc % PAGE_SIZE == 0
  end

  def oper_imm
    @mem[@pc]
  end

  def oper_zp
    @mem[@mem[@pc]]
  end

  def oper_zpx
    @mem[@mem[@pc] + @reg["x"]]
  end

  def oper_abs
    read_word(read_word(@pc))
  end

  def oper_absx
    read_word(read_word(@pc) + @reg["x"])
  end

  def oper_absx
    read_word(read_word(@pc) + @reg["y"])
  end

  def oper_indx
    @mem[(@pc + @reg["x"]) & 0xff]
  end

  def oper_indy
    @mem[@pc + @reg["y"]]
  end
  
  def run
    @running = true
    while @running do
      cycle
    end
  end

  def pause
    @running = false
  end

  def cycle
    op = @mem[@pc]
    ticks = 0
    time = Time.new
    case op

    # ADC
    when 0x69, 0x65, 0x75, 0x6d, 0x7d, 0x79, 0x61, 0x71
      @pc += 1
      case op
      # IMM
      when 0x69
        @reg["a"] += oper_imm
        ticks = 2
      # ZP
      when 0x65
        @reg["a"] += oper_zp
        ticks = 3
      # ZP, X
      when 0x75
        @reg["a"] += oper_zpx
        ticks = 4
      # ABS
      when 0x6d
        @reg["a"] += oper_abs
        @pc += 1
        ticks = 4
      # ABS, X
      when 0x7d
        @reg["a"] += oper_absx
        ticks += 1 if page_boundary?
        @pc += 1
        ticks += 1 if page_boundary?
        ticks += 4
      # ABS, Y
      when 0x79
        @reg["a"] += oper_absy
        ticks += 1 if page_boundary?
        @pc += 1
        ticks += 1 if page_boundary?
        ticks += 4
      # IND, X
      when 0x61
        @reg["a"] += oper_indx
        ticks = 6
      # IND, Y
      when 0x71
        @reg["a"] += oper_indy
        ticks += 1 if page_boundary?
        ticks += 5
      end
      
      if @reg["a"] > 0xff
        @reg["p"] &= 0b00000001
        @reg["a"] -= 0xff
      elsif @reg["a"] == 0
        @reg["p"] &= 0b00000010
      end
      @reg["p"] &= @reg["a"] & 0b10000000

    # AND
    when 0x29, 0x25, 0x35, 0x2d, 0x3d, 0x39, 0x21, 0x31
      case op

      # IMM
      when 0x29
        @reg["a"] &= oper_imm
        ticks = 2
      # ZP
      when 0x25
        @reg["a"] &= oper_zp
        ticks = 3
      # ZP, X
      when 0x35
        @reg["a"] &= oper_zpx
        ticks = 4
      # ABS
      when 0x2d
        @reg["a"] &= oper_abs
        @pc += 1
        ticks = 4
      # ABS, X
      when 0x3d
        @reg["a"] &= oper_absx
        ticks += 1 if page_boundary?
        @pc += 1
        ticks += 1 if page_boundary?
        ticks += 4
      # ABS, Y
      when 0x39
        @reg["a"] &= oper_absy
        ticks += 1 if page_boundary?
        @pc += 1
        ticks += 1 if page_boundary?
        ticks += 4
      # IND, X
      when 0x21
        @reg["a"] &= oper_indx
        ticks = 6
      # IND, Y
      when 0x31
        @reg["a"] &= oper_indy
        ticks = 5
        
      end

      @reg["p"] &= 0b00000010 if @reg["a"] == 0
      @reg["p"] &= @reg["a"] & 0b10000000

    # ASL
    when 0x0a, 0x06, 0x16, 0x0e, 0x1e
      case op

      # ACC
      when 0x0a
        @reg["a"] <<= 1
        ticks = 2
      # ZP
      when 0x06
        @reg["a"] = oper_zp << 1
        ticks = 5
      # ZP, X
      when 0x16
        @reg["a"] = oper_zpx << 1
        ticks = 6
      # ABS
      when 0x0e
        @reg["a"] = oper_abs << 1
        @pc += 1
        ticks = 6
      # ABS, X
      when 0x1e
        @reg["a"] = oper_absx << 1
        @pc += 1
        ticks = 7
          
      end

      if @reg["a"] > 0xff
        @reg["p"] &= 0b00000001
        @reg["a"] -= 0xff
      elsif @reg["a"] == 0
        @reg["p"] &= 0b00000010
      end
      @reg["p"] &= @reg["a"] & 0b10000000

    # BCC
    when 0x90
      @pc += signed_int(oper_imm) unless flag_c?
      ticks = 2

    # BCS
    when 0xb0
      @pc += signed_int(oper_imm) if flag_c?
      ticks = 2

    # BEQ
    when 0xf0
      @pc += signed_int(oper_imm) if flag_z?
      ticks = 2

    # BIT
    when 0x24, 0x2c
      
    # BMI
    when 0x30
      @pc += signed_int(oper_imm) if flag_n?
      ticks = 2

    # BNE
    when 0xd0
      @pc += signed_int(oper_imm) unless flag_z?
      ticks = 2

    # BPL
    when 0x10
      @pc += signed_int(oper_imm) unless flag_n?
      ticks = 2

    # BRK
    when 0x00
      @pc = IRQ_ADDRESS
      @reg["p"] = 0b00010100
      ticks = 7
      
    else
      # UNKNOWN INSTRUCTION
      ticks = 1
      
    end

    @pc += 1
    time = Time.new - time
    delay = 1.0 / FREQUENCY * ticks - time
    return if delay < 0
    sleep(delay)
   end
end
