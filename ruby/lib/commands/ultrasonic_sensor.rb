# ruby-nxt Control Mindstorms NXT via Bluetooth Serial Port Connection
# Copyright (C) 2006 Tony Buser <tbuser@gmail.com> - http://juju.org
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

# Implements the "Ultrasonic Sensor" block in NXT-G
class Commands::UltrasonicSensor

  attr_reader :port
  attr_accessor :mode, :trigger_point, :comparison
  
  def initialize(nxt)
    @nxt      = nxt
    
    # defaults the same as NXT-G
    @port           = 4
    @trigger_point  = 50
    @comparison     = "<"
    @mode           = :inches
    set_mode
  end

  def port=(port)
    @port = port
    set_mode
  end

  # returns true or false based on comparison and trigger point
  def logic
    case @comparison
      when ">"
        distance >= @trigger_point ? true : false
      when "<"
        distance <= @trigger_point ? true : false
    end
  end
  
  # returns distance in requested mode (:inches or :centimeters)
  def distance
    @nxt.ls_write(NXTComm.const_get("SENSOR_#{@port}"), [0x02, 0x01, 0x02, 0x42])
    
    # Keep checking until we have data to read
    while @nxt.ls_get_status(NXTComm.const_get("SENSOR_#{@port}")) < 1
      sleep(0.1)
      # TODO: implement timeout so we don't get stuck if the expected data never comes
    end
    
    distance = @nxt.ls_read(NXTComm.const_get("SENSOR_#{@port}"))[:data][0]
 		
 		if @mode == :centimeters
 		  distance.inspect
	  else
	    (distance * 0.3937008).to_i
    end
  end
  
  # sets up the sensor port
  def set_mode
    @nxt.set_input_mode(
      NXTComm.const_get("SENSOR_#{@port}"),
      NXTComm::LOWSPEED_9V,
      NXTComm::RAWMODE
    )
    # clear buffer
    @nxt.ls_read(NXTComm.const_get("SENSOR_#{@port}"))
    # set sensor to continuously send pings
    @nxt.ls_write(NXTComm.const_get("SENSOR_#{@port}"), [0x03, 0x00, 0x02, 0x41, 0x02])
  end
end
