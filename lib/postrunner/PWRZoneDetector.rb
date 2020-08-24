#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = PWRZoneDetector.rb -- PostRunner - Calculates time spent in power zones, adjusted 7 zones + sweetspot.
# ref: Allen & Coggan, Training with a Power Meter
# ref: FasCat Coaching
#
# Copyright (c) 2017 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
#
# zone  min max (as % of FTP)
#   0   0   10  Rest
#   1   10  55  Active Recovery
#   2   55  75  Endurance
#   3   75  90  Tempo
#   4   83  97  Sweet Spot
#   5   90  105 Threshold
#   6   105 120 VO2 Max
#   7   120 150 Anaerobic Capacity
#   8   150 +   Neuromuscular Power

module PostRunner

  module PWRZoneDetector

    class PWRZone < Struct.new(:index, :low, :high, :time_in_zone, :percent_in_zone)
    end

    # Number of power zones (see defintions above)
    PWR_ZONES = 9
    # Maximum power (guess)
    MAX_PWR = 2000
    PWR_ZONE_BREAKS = [[0,10],[10,55],[55,75],[75,90],[83,97],[90,105],[105,120],[120,150],[150,999]]
    

    def PWRZoneDetector::detect_zones(fit_records, ftp)
      if fit_records.empty?
        raise RuntimeError, "records must not be empty"
      end

     zones = []
     total_time = 0
     0.upto(PWR_ZONES-1) do |i|
        #binding.pry    #jkk
        low = PWR_ZONE_BREAKS[i][0] * ftp / 100
        i==0 ? low = low.floor : low = low.floor + 1
        high = PWR_ZONE_BREAKS[i][1] * ftp / 100
        high  = high.floor
        high = MAX_PWR if high > MAX_PWR
        zones << PWRZone.new(i, low, high, 0, 0)
     end        

     #binding.pry   #jkk
  
      # run through each record, incrementing each power zone if power is within that zone 
      # (allows for multiple power zones at a time as you get with sweet spot zone
      last_timestamp = nil
      fit_records.each do |record|
        next unless record.power

        if last_timestamp
          # We ignore all intervals that are larger than 600 (was 10) seconds. This
          # potentially conflicts with smart recording, but I can't see how a
          # larger sampling interval can yield usable results.
          if (delta_t = record.timestamp - last_timestamp) <= 600
          #  binding.pry     #jkk
            record.power < MAX_PWR ? current_power = record.power: current_power = MAX_PWR
            total_time += delta_t
            0.upto(PWR_ZONES-1) do |i|
                if current_power >= zones[i][:low] && current_power <= zones[i][:high]
                    zones[i][:time_in_zone] += delta_t
                end
            end
          else 
            puts "delta_t = #{delta_t}"
            binding.pry         #jkk
          end
        end
        last_timestamp = record.timestamp
      end  #record do loop

      #binding.pry #jkk

      0.upto(PWR_ZONES-1) do |i|
        zones[i][:percent_in_zone] = zones[i][:time_in_zone] * 100 / total_time
        zones[i][:percent_in_zone] = zones[i][:percent_in_zone].round
      end

      #binding.pry  #jkk

      return zones
    end  # detect_zones

  end

end

