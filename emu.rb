#!/usr/bin/env ruby

$:.unshift(__dir__)

require "e65"

cpu = E65.new
cpu.run
