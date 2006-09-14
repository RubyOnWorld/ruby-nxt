# ruby-nxt Control Mindstorms NXT via Bluetooth Serial Port Connection
# Copyright (C) 2006 Tony Buser <tbuser@gmail.com> - juju.org
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

# http://raa.ruby-lang.org/project/ruby-serialport/
require "serialport"
require "thread"

class Array
  def to_hex_str
    self.collect{|e| "0x%02x " % e}
  end
end

class String
  def to_hex_str
    str = ""
    self.each_byte {|b| str << '0x%02x ' % b}
    str
  end
  
  def from_hex_str
  	data = self.split(' ')
  	str = ""
  	data.each{|h| eval "str += '%c' % #{h}"}
  	str
  end
end

class Bignum
  # This is needed because String#unpack() can't handle little-endian signed longs...
  # instead we unpack() as a little-endian unsigned long (i.e. 'V') and then use this
  # method to convert to signed long.
  def as_signed
  	-1*(self^0xffffffff) if self > 0xfffffff
  end
end

# = Description
#
# Low-level interface for communicating directly with the NXT via
# a Bluetooth serial port.  Implements direct commands outlined in
# Appendix 2-LEGO MINDSTORMS NXT Direct Commands.pdf
# 
# Not all functionality is implemented yet!
# 
# For instructions on creating a bluetooth serial port connection:
# * Linux: http://www.jstuber.net/lego/nxt-programming/bluetooth-linux.html
# * OSX: http://juju.org/articles/2006/08/01/mindstorms-nxt-bluetooth-on-osx
# * Windows: http://juju.org/articles/2006/08/16/ruby-serialport-nxt-on-windows
#
# =Examples
#
# First create a new NXTComm object and pass the device.
#
#   @nxt = NXTComm.new("/dev/tty.NXT-DevB-1")
# 
# Rotate the motor connected to port B forwards indefinitely at 100% power:
#
#   @nxt.set_output_state(
#     NXTComm::MOTOR_B,
#     100,
#     NXTComm::MOTORON,
#     NXTComm::REGULATION_MODE_MOTOR_SPEED,
#     100,
#     NXTComm::MOTOR_RUN_STATE_RUNNING,
#     0
#   )
# 
# Play a tone at 1000 Hz for 500 ms:
#
#   @nxt.play_tone(1000,500)
# 
# Print out the current battery level:
#
#   puts "Battery Level: #{@nxt.get_battery_level/1000.0} V"
#
class NXTComm

  # sensors
  SENSOR_1  = 0x00
  SENSOR_2  = 0x01
  SENSOR_3  = 0x02
  SENSOR_4  = 0x03
  
  # motors
  MOTOR_A   = 0x00
  MOTOR_B   = 0x01
  MOTOR_C   = 0x02
  MOTOR_ALL = 0xFF
  
  # output mode
  MOTORON   = 0x01
  BRAKE     = 0x02
  REGULATED = 0x04
  
  # output regulation mode
  REGULATION_MODE_IDLE        = 0x00
  REGULATION_MODE_MOTOR_SPEED = 0x01
  REGULATION_MODE_MOTOR_SYNC  = 0x02
  
  # output run state
  MOTOR_RUN_STATE_IDLE        = 0x00
  MOTOR_RUN_STATE_RAMPUP      = 0x10
  MOTOR_RUN_STATE_RUNNING     = 0x20
  MOTOR_RUN_STATE_RAMPDOWN    = 0x40
  
  # sensor type
  NO_SENSOR           = 0x00
  SWITCH              = 0x01
  TEMPERATURE         = 0x02
  REFLECTION          = 0x03
  ANGLE               = 0x04
  LIGHT_ACTIVE        = 0x05
  LIGHT_INACTIVE      = 0x06
  SOUND_DB            = 0x07
  SOUND_DBA           = 0x08
  CUSTOM              = 0x09
  LOWSPEED            = 0x0A
  LOWSPEED_9V         = 0x0B
  NO_OF_SENSOR_TYPES  = 0x0C
  
  # sensor mode
  RAWMODE             = 0x00
  BOOLEANMODE         = 0x20
  TRANSITIONCNTMODE   = 0x40
  PERIODCOUNTERMODE   = 0x60
  PCTFULLSCALEMODE    = 0x80
  CELSIUSMODE         = 0xA0
  FAHRENHEITMODE      = 0xC0
  ANGLESTEPSMODE      = 0xE0
  SLOPEMASK           = 0x1F
  MODEMASK            = 0xE0
  
  @@op_codes = {
    'start_program'             => 0x00,
    'stop_program'              => 0x01,
    'play_sound_file'           => 0x02,
    'play_tone'                 => 0x03,
    'set_output_state'          => 0x04,
    'set_input_mode'            => 0x05,
    'get_output_state'          => 0x06,
    'get_input_values'          => 0x07,
    'reset_input_scaled_value'  => 0x08,
    'message_write'             => 0x09,
    'reset_motor_position'      => 0x0A,
    'get_battery_level'         => 0x0B,
    'stop_sound_playback'       => 0x0C,
    'keep_alive'                => 0x0D,
    'ls_get_status'             => 0x0E,
    'ls_write'                  => 0x0F,
    'ls_read'                   => 0x10,
    'get_current_program_name'  => 0x11,
    # what happened to 0x12?  Dunno...
    'message_read'              => 0x13
  }
  
  @@error_codes = {
    0x20 => "Pending communication transaction in progress",
    0x40 => "Specified mailbox queue is empty",
    0xBD => "Request failed (i.e. specified file not found)",
    0xBE => "Unknown command opcode",
    0xBF => "Insane packet",
    0xC0 => "Data contains out-of-range values",
    0xDD => "Communication bus error",
    0xDE => "No free memory in communication buffer",
    0xDF => "Specified channel/connection is not valid",
    0xE0 => "Specified channel/connection not configured or busy",
    0xEC => "No active program",
    0xED => "Illegal size specified",
    0xEE => "Illegal mailbox queue ID specified",
    0xEF => "Attempted to access invalid field of a structure",
    0xF0 => "Bad input or output specified",
    0xFB => "Insufficient memory available",
    0xFF => "Bad arguments"
  }
  
  @@devs = {}

	# Create a new instance of NXTComm.
	# This NXTComm object will share its serialport connection
	# IO object with all other instances. This way we can ensure thread
	# safety for NXTComm instances in different threads.
  def initialize(dev)
    @dev = dev
    @sp = nil

		@mutex = Mutex.new
@mutex.synchronize do
  	begin
  		if @@devs.include? dev and not @@devs[dev].closed?
  			@sp = @@devs[dev]
  		else
    		@@devs[dev] = @sp = SerialPort.new(@dev, 57600, 8, 1, SerialPort::NONE)
    	end
    rescue Errno::EBUSY
    	raise "Cannot connect to #{@dev}. The serial port is busy or unavailable."
    end
    
    @sp.flow_control = SerialPort::HARD
    @sp.read_timeout = 5000
end
    if @sp.nil?
      $stderr.puts "Cannot connect to #{@dev}"
    else
      puts "Connected to: #{@dev}" if $DEBUG
    end
  end

  # Close the connection
  def close
  	@mutex.synchronize do
    	@sp.close if @sp and not @sp.closed?
  	end
  end
  
  # Returns true if the connection to the NXT is open; false otherwise
  def connected?
  	not @sp.closed?
  end

  # Send message and return response
  def send_and_receive(op,cmd)
    msg = [op] + cmd + [0x00]
    
    send_cmd(msg)
    len,ret = recv_reply
    
    if (ret[1] == op)
      data = ret[3..ret.size]
      # TODO ? if data contains a \n character, ruby seems to pass the parts before and after the \n
      # as two different parameters... we need to encode the data into a format that doesn't
      # contain any \n's and then decode it in the receiving method
      data = data.to_hex_str
    else
      $stderr.puts "ERROR: Could not decode returned msg for #{cmd_str}"
      data = nil
    end
    data
  end
  
  # Send direct command bytes
  def send_cmd(msg)
  	@mutex.synchronize do
	  	msg = [0x00] + msg # always request a response
	    #puts "Message Size: #{msg.size}" if $DEBUG
	    msg = [(msg.size & 255),(msg.size >> 8)] + msg
	    puts "Sending Message: #{msg.to_hex_str}" if $DEBUG
	    msg.each do |b|
	      @sp.putc b
	    end
	  end
  end
  
  # Process the reply
  def recv_reply
  	@mutex.synchronize do
	    while (len_header = @sp.sysread(2))
	      msg = @sp.sysread(len_header.unpack("v")[0])
	      puts "Received Message: #{len_header.to_hex_str}#{msg.to_hex_str}" if $DEBUG
	      
	      if msg[0] != 0x02
	        $stderr.puts "ERROR: Returned something other then a reply telegram"
	        return [0,msg]
	      end
	      
	      if msg[2] != 0x00
	        $stderr.puts "ERROR: #{@@error_codes[msg[2]]}"
	        return [0,msg]
	      end
	      
	      return[msg.size,msg]
	    end
    end
  end

  # Start a program stored on the NXT.
  # * <tt>name</tt> - file name of the program
  def start_program(name)
    cmd = []
    name.each_byte do |b|
      cmd << b
    end
    send_and_receive @@op_codes["start_program"], cmd
  end

  # Stop any programs currently running on the NXT.
  def stop_program
    cmd = []
    send_and_receive @@op_codes["stop_program"], cmd
  end

  # Play a sound file stored on the NXT.
  # * <tt>name</tt> - file name of the sound file to play
  # * <tt>repeat</tt> - Loop? (true or false)
  def play_sound_file(name,repeat = false)
    cmd = []
    repeat ? cmd << 0x01 : cmd << 0x00
    name.each_byte do |b|
      cmd << b
    end
    send_and_receive @@op_codes["play_sound_file"], cmd
  end

  # Play a tone.
  # * <tt>freq</tt> - frequency for the tone in Hz
  # * <tt>dur</tt> - duration for the tone in ms
  def play_tone(freq,dur)
    cmd = [(freq & 255),(freq >> 8),(dur & 255),(dur >> 8)]
    send_and_receive @@op_codes["play_tone"], cmd
  end

  # Set various parameters for the output motor port(s).
  # * <tt>port</tt> - output port (MOTOR_A, MOTOR_B, MOTOR_C, or MOTOR_ALL)
  # * <tt>power</tt> - power set point (-100 - 100)
  # * <tt>mode</tt> - output mode (MOTORON, BRAKE, REGULATED)
  # * <tt>reg_mode</tt> - regulation mode (REGULATION_MODE_IDLE, REGULATION_MODE_MOTOR_SPEED, REGULATION_MODE_MOTOR_SYNC)
  # * <tt>turn_ratio</tt> - turn ratio (-100 - 100)
  # * <tt>run_state</tt> - run state (MOTOR_RUN_STATE_IDLE, MOTOR_RUN_STATE_RAMPUP, MOTOR_RUN_STATE_RUNNING, MOTOR_RUN_STATE_RAMPDOWN)
  # * <tt>tacho_limit</tt> - tacho limit (number, 0 - run forever)
  def set_output_state(port,power,mode,reg_mode,turn_ratio,run_state,tacho_limit)
    cmd = [port,power,mode,reg_mode,turn_ratio,run_state] + [tacho_limit].pack("V").unpack("C4")
    send_and_receive @@op_codes["set_output_state"], cmd
  end

  # Set various parameters for an input sensor port.
  # * <tt>port</tt> - input port (SENSOR_1, SENSOR_2, SENSOR_3, SENSOR_4)
  # * <tt>type</tt> - sensor type (NO_SENSOR, SWITCH, TEMPERATURE, REFLECTION, ANGLE, LIGHT_ACTIVE, LIGHT_INACTIVE, SOUND_DB, SOUND_DBA, CUSTOM, LOWSPEED, LOWSPEED_9V, NO_OF_SENSOR_TYPES)
  # * <tt>mode</tt> - sensor mode (RAWMODE, BOOLEANMODE, TRANSITIONCNTMODE, PERIODCOUNTERMODE, PCTFULLSCALEMODE, CELSIUSMODE, FAHRENHEITMODE, ANGLESTEPMODE, SLOPEMASK, MODEMASK)
  def set_input_mode(port,type,mode)
    cmd = [port,type,mode]
    send_and_receive @@op_codes["set_input_mode"], cmd
  end
  
  # Get the state of the output motor port.
  # * <tt>port</tt> - output port (MOTOR_A, MOTOR_B, MOTOR_C)
  # Returns a hash with the following info (enumerated values see: set_output_state):
  #   {
  #     :port               => see: output ports,
  #     :power              => -100 - 100,
  #     :mode               => see: output modes,
  #     :reg_mode           => see: regulation modes,
  #     :turn_ratio         => -100 - 100,
  #     :run_state          => see: run states,
  #     :tacho_limit        => current limit on a movement in progress, if any,
  #     :tacho_count        => internal count, number of counts since last reset of the motor counter,
  #     :block_tacho_count  => current position relative to last programmed movement,
  #     :rotation_count     => current position relative to last reset of the rotation sensor for this motor
  #   }
  def get_output_state(port)
    cmd = [port]
    resp = send_and_receive @@op_codes["get_output_state"], cmd

    resp_parts = resp.from_hex_str.unpack('C6VVVV')
    (7..9).each do |i|
      resp_parts[i] = resp_parts[i].as_signed if resp_parts[i].kind_of? Bignum
    end
    
    {
      :port               => resp_parts[0],
      :power              => resp_parts[1],
      :mode               => resp_parts[2],
      :reg_mode           => resp_parts[3],
      :turn_ratio         => resp_parts[4],
      :run_state          => resp_parts[5],
      :tacho_limit        => resp_parts[6],
      :tacho_count        => resp_parts[7],
      :block_tacho_count  => resp_parts[8],
      :rotation_count     => resp_parts[9]
    }
  end
  # Get the state of the output motor port.
  # * <tt>port</tt> - output port (MOTOR_A, MOTOR_B, MOTOR_C)
  # Returns a hash with the following info (enumerated values see: set_output_state):
  #   {
  #     :port               => see: output ports,
  #     :power              => -100 - 100,
  #     :mode               => see: output modes,
  #     :reg_mode           => see: regulation modes,
  #     :turn_ratio         => -100 - 100,
  #     :run_state          => see: run states,
  #     :tacho_limit        => current limit on a movement in progress, if any,
  #     :tacho_count        => internal count, number of counts since last reset of the motor counter,
  #     :block_tacho_count  => current position relative to last programmed movement,
  #     :rotation_count     => current position relative to last reset of the rotation sensor for this motor
  #   }
  def get_output_state(port)
    cmd = [port]
    resp = send_and_receive @@op_codes["get_output_state"], cmd

    resp_parts = resp.from_hex_str.unpack('C6VVVV')
    (7..9).each do |i|
      resp_parts[i] = resp_parts[i].as_signed if resp_parts[i].kind_of? Bignum
    end
    
    {
      :port               => resp_parts[0],
      :power              => resp_parts[1],
      :mode               => resp_parts[2],
      :reg_mode           => resp_parts[3],
      :turn_ratio         => resp_parts[4],
      :run_state          => resp_parts[5],
      :tacho_limit        => resp_parts[6],
      :tacho_count        => resp_parts[7],
      :block_tacho_count  => resp_parts[8],
      :rotation_count     => resp_parts[9]
    }
  end
  
  # Get the current values from an input sensor port.
  # * <tt>port</tt> - input port (SENSOR_1, SENSOR_2, SENSOR_3, SENSOR_4)
  # Returns a hash with the following info (enumerated values see: set_input_mode):
  #   {
  #     :port             => see: input ports,
  #     :valid            => boolean, true if new data value should be seen as valid data, 
  #     :calibrated       => boolean, true if calibration file found and used for 'Calibrated Value' field below, 
  #     :type             => see: sensor types, 
  #     :mode             => see: sensor modes, 
  #     :value_raw        => raw A/D value (device dependent),
  #     :value_normal     => normalized A/D value (0 - 1023),
  #     :value_scaled     => scaled value (mode dependent),
  #     :value_calibrated => calibrated value, scaled to calibration (CURRENTLY UNUSED)
  #   }
  def get_input_values(port)
    cmd = [port]
    resp = send_and_receive @@op_codes["get_input_values"], cmd

    resp_parts = resp.from_hex_str.unpack('C5S2s2')
    resp_parts[1] = 0x01 ? resp_parts[1] = true : resp_parts[1] = false
    resp_parts[2] = 0x01 ? resp_parts[2] = true : resp_parts[2] = false

    {
      :port             => resp_parts[0],
      :valid            => resp_parts[1],
      :calibrated       => resp_parts[2],
      :type             => resp_parts[3],
      :mode             => resp_parts[4],
      :value_raw        => resp_parts[5],
      :value_normal     => resp_parts[6],
      :value_scaled     => resp_parts[7],
      :value_calibrated => resp_parts[8],
    }
  end

  # Reset the scaled value on an input sensor port.
  # * <tt>port</tt> - input port (SENSOR_1, SENSOR_2, SENSOR_3, SENSOR_4)
  def reset_input_scaled_value(port)
    cmd = [port]
    send_and_receive @@op_codes["reset_input_scaled_value"], cmd
  end

  # Write a message to a specific inbox on the NXT.  This is used to send a message to a currently running program.
  # * <tt>inbox</tt> - inbox number (1 - 10)
  # * <tt>message</tt> - message data
  def message_write(inbox,message)
    cmd = []
    cmd << inbox - 1
    cmd << message.size + 1
    message.each_byte do |b|
      cmd << b
    end
    send_and_receive @@op_codes["message_write"], cmd
  end

  # Reset the position of an output motor port.
  # * <tt>port</tt> - output port (MOTOR_A, MOTOR_B, MOTOR_C)
  # * <tt>relative</tt> - boolean, true - position relative to last movement, false - absolute position
  def reset_motor_position(port,relative = false)
    cmd = []
    cmd << port
    relative ? cmd << 0x01 : cmd << 0x00
    send_and_receive @@op_codes["reset_motor_position"], cmd
  end
  
  # Returns the battery voltage in millivolts.
  def get_battery_level
    cmd = []
    resp = send_and_receive @@op_codes["get_battery_level"], cmd
    resp.from_hex_str.unpack("v")[0]
  end

  # Stop any currently playing sounds.
  def stop_sound_playback
    cmd = []
    send_and_receive @@op_codes["stop_sound_playback"], cmd
  end

  # Keep the connection alive? Also, returns the current sleep time limit in ms
  def keep_alive
    cmd = []
    resp = send_and_receive @@op_codes["keep_alive"], cmd
    resp.from_hex_str.unpack("L")[0]
  end

  # TODO Get the status of an LS port?  Returns the count of available bytes to read.
  # * <tt>port</tt> - input port (SENSOR_1, SENSOR_2, SENSOR_3, SENSOR_4)
  def ls_get_status(port)
    cmd = [port]
    resp = send_and_receive @@op_codes["ls_get_status"], cmd
    resp
  end
  
  # Write data to lowspeed I2C port (for talking to the ultrasonic sensor)
  # * <tt>port</tt> - input port (SENSOR_1, SENSOR_2, SENSOR_3, SENSOR_4)
  # * <tt>tx_len</tt> - Tx data length (bytes)
  # * <tt>rx_len</tt> - Rx data length (bytes)
  # * <tt>data</tt> - Tx data
  #
  #   For LS communication on the NXT, data lengths are limited to 16 bytes per command.  Rx data length
  #   MUST be specified in the write command since reading from the device is done on a master-slave basis
  def ls_write(port,tx_len,rx_len,data)
    cmd = [port,tx_len,rx_len,data]
    send_and_receive @@op_codes["ls_write"], cmd
  end
  
  # Read data from from lowspeed I2C port (for talking to the ultrasonic sensor)
  # * <tt>port</tt> - input port (SENSOR_1, SENSOR_2, SENSOR_3, SENSOR_4)
  # Returns a hash containing:
  #   {
  #     :bytes_read => number of bytes read
  #     :data       => Rx data (padded)
  #   }
  #
  #   For LS communication on the NXT, data lengths are limited to 16 bytes per command.
  #   Furthermore, this protocol does not support variable-length return packages, so the response
  #   will always contain 16 data bytes, with invalid data bytes padded with zeroes.
  def ls_read(port)
    cmd = [port]
    resp = send_and_receive @@op_codes["ls_read"], cmd
    {
      :bytes_read => resp[0],
      :data       => resp[1..-1]
    }
  end
  
  # Returns the name of the program currently running on the NXT.
  # Returns an error If no program is running.
  def get_current_program_name
    cmd = []
    resp = send_and_receive @@op_codes["get_current_program_name"], cmd
    resp.from_hex_str.unpack("A*")[0]
  end

  # Read a message from a specific inbox on the NXT.
  # * <tt>inbox_remote</tt> - remote inbox number (1 - 10)
  # * <tt>inbox_local</tt> - local inbox number (1 - 10) (not sure why you need this?)
  # * <tt>remove</tt> - boolean, true - clears message from remote inbox
  def message_read(inbox_remote,inbox_local,remove = false)
    cmd = [inbox_remote, inbox_local]
    remove ? cmd << 0x01 : cmd << 0x00
    resp = send_and_receive @@op_codes["message_read"], cmd
    resp[2..-1].from_hex_str.unpack("A*")[0]
  end
end
