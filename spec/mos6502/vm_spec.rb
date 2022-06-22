# frozen_string_literal: true

require 'mos6502'

RSpec.describe MOS6502::VM do
  vm = described_class.new

  it 'Reset VM' do
    expect(vm.memory.all?(0)).to be(true)
    expect(vm.ra).to eq(0)
    expect(vm.rx).to eq(0)
    expect(vm.ry).to eq(0)
    expect(vm.pc).to eq(vm.entry_address)
    expect(vm.sp).to eq(described_class::STACK_ADDRESS)
    expect(vm.flags).to eq(0)
  end

  it 'Load memory' do
    data = "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f"
    vm.load_memory(data)
    expect(vm.memory[vm.entry_address, data.bytesize]).to eq(data.bytes)
  ensure
    vm.reset
  end

  it 'Opcode ADC' do
    data = "\x69\x05\x69\x09\x69\xfa\x69\xe0\x69\x0f"
    vm.instance_variable_set(:@ra, 0x18)
    vm.load_memory(data)
    vm.step
    expect(vm.ra).to eq(0x1d)
    expect(vm.flags).to eq(0x00)
    expect(vm.cycles).to eq(2)
    vm.step
    expect(vm.ra).to eq(0x26)
    expect(vm.flags).to eq(0x00)
    expect(vm.cycles).to eq(4)
    vm.step
    expect(vm.ra).to eq(0x20)
    expect(vm.flags).to eq(0x01)
    expect(vm.cycles).to eq(6)
    vm.instance_variable_set(:@flags, 0)
    vm.step
    expect(vm.ra).to eq(0x00)
    expect(vm.flags).to eq(0x03)
    expect(vm.cycles).to eq(8)
    vm.step
    expect(vm.ra).to eq(0x10)
    expect(vm.flags).to eq(0x00)
    expect(vm.cycles).to eq(10)
  ensure
    vm.reset
  end

  it 'Opcode AND' do
    data = "\x29\x51\x29\x14"
    vm.load_memory(data)
    vm.instance_variable_set(:@ra, 0xee)
    vm.step
    expect(vm.ra).to eq(0x40)
    expect(vm.flags).to eq(0x00)
    expect(vm.cycles).to eq(2)
    vm.step
    expect(vm.ra).to eq(0x00)
    expect(vm.flags).to eq(0x02)
    expect(vm.cycles).to eq(4)
  ensure
    vm.reset
  end

  it 'Opcode ASL' do
    data = "\x0a\x0a\x0a"
    vm.load_memory(data)
    vm.instance_variable_set(:@ra, 0x02)
    vm.step
    expect(vm.ra).to eq(0x04)
    expect(vm.cycles).to eq(2)
    vm.step
    expect(vm.ra).to eq(0x08)
    expect(vm.cycles).to eq(4)
    vm.instance_variable_set(:@ra, 0x41)
    vm.step
    expect(vm.ra).to eq(0x82)
    expect(vm.cycles).to eq(6)
  ensure
    vm.reset
  end

  it 'Opcode BIT' do
    data = "\x24\x02"
    vm.load_memory(data)
    zp = "\x00\x00\x95"
    vm.load_memory(zp, offset: 0)
    vm.step
    expect(vm.flags).to eq(0x82)
  ensure
    vm.reset
  end

  it 'Opcode NOP' do
    data = "\xea\xea\xea\xea\xea"
    vm.load_memory(data)
    data.each_byte.with_index do |_, i|
      expect(vm.pc).to eq(vm.entry_address + i)
      vm.step
      expect(vm.cycles).to eq((i + 1) * 2)
    end
  ensure
    vm.reset
  end
end
