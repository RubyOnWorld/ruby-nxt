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

# Implements the "Touch Sensor" block in NXT-G
class Commands::TouchSensor

  attr_reader :port, :action
  
  def initialize(nxt)
    @nxt      = nxt
    
    # defaults the same as NXT-G
    @port   = 1
    @action = :pressed
    set_mode
  end

  def port=(port)
    @port = port
    set_mode
  end

  def action=(action)
    @action = action
    set_mode
  end

  # returns true or false based on action type
  def logic
    state = @nxt.get_input_values(NXTComm.const_get("SENSOR_#{@port}"))
    case @action
      when :pressed
        state[:value_scaled] > 0 ? true : false
      when :released
        state[:value_scaled] > 0 ? false : true
      when :bumped
        state[:value_scaled] > 0 ? true : false
    end
  end
  
  # returns the raw value of the sensor
  # TODO this method should probably be shared between all sensor commands
  def raw_value
    @nxt.get_input_values(NXTComm.const_get("SENSOR_#{@port}"))[:value_raw]
  end
  
  # resets the value_scaled property, use this to reset the sensor when in :bumped mode
  def reset
    @nxt.reset_input_scaled_value(NXTComm.const_get("SENSOR_#{@port}"))
  end
  
  # sets up the sensor port
  def set_mode
    @action == :bumped ? mode = NXTComm::PERIODCOUNTERMODE : mode = NXTComm::BOOLEANMODE
    @nxt.set_input_mode(
      NXTComm.const_get("SENSOR_#{@port}"),
      NXTComm::SWITCH,
      mode
    )
  end
  
  # attempt to return the input_value requested
  def method_missing(cmd)
    state = {}
    state = @nxt.get_input_values(NXTComm.const_get("SENSOR_#{@port}"))[cmd]
    state
  end
end
