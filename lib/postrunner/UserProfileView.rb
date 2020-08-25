#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = UserProfileView.rb -- PostRunner - Manage the data from your Garmin sport devices.
#
# Copyright (c) 2014 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'fit4ruby'

require 'postrunner/ViewFrame'

module PostRunner

  class UserProfileView

    include Fit4Ruby::Converters

    def initialize(fit_activity, unit_system)
      @fit_activity = fit_activity
      @unit_system = unit_system
    end

    def to_html(doc)
      return nil if @fit_activity.user_data.empty?

      ViewFrame.new('user_profile', 'User Profile', 600, profile,
                    true).to_html(doc)
    end

    def to_s
      return '' if @fit_activity.user_data.empty?
      profile.to_s
    end

    private

    def profile
      t = FlexiTable.new

      user_data = @fit_activity.user_data.first
      user_profile = @fit_activity.user_profiles.first
      hr_zones = @fit_activity.heart_rate_zones.first

      if user_data && user_data.height
        unit = { :metric => 'm', :statute => 'ft' }[@unit_system]
        height = user_data.get_as('height', unit)
        t.cell('Height:', { :width => '40%' })
        t.cell("#{'%.2f' % height} #{unit}", { :width => '60%' })
        t.new_row
      end
      if (user_data && user_data.weight) || (user_profile && user_profile.weight)
        unit = { :metric => 'kg', :statute => 'lbs' }[@unit_system]
        weight = (user_profile && user_profile.get_as('weight', unit)) ||
                 (user_data && user_data.get_as('weight', unit))
        t.row([ 'Weight:', "#{'%.1f' % weight} #{unit}" ])
      end
      t.row([ 'Gender:', user_data.gender ]) if user_data.gender
      t.row([ 'Age:', "#{user_data.age} years" ]) if user_data.age
      if (user_profile && (rest_hr = user_profile.resting_heart_rate)) ||
         (hr_zones && (rest_hr = hr_zones.resting_heart_rate))
        t.row([ 'Resting Heart Rate:', "#{rest_hr} bpm" ])
      end
      if (max_hr = user_data.max_hr) ||
         (max_hr = hr_zones.max_heart_rate)
        t.row([ 'Max. Heart Rate:', "#{max_hr} bpm" ])
      end
      if user_profile && (date = user_profile.time_last_lthr_update)
        t.row([ 'Last Lactate Threshold Update:', date ])
      end
      if user_data && (lthr = user_data.running_lactate_threshold_heart_rate)
        t.row([ 'Running LT Heart Rate:', "#{lthr} bpm" ])
      end
      if user_profile && (speed = user_profile.functional_threshold_speed)
        unit = { :metric => 'min/km', :statute => 'min/mile' }[@unit_system]
        t.row([ 'Running LT Pace:', "#{speedToPace(speed)} #{unit}" ])
      end
      if (activity_class = user_data.activity_class)
        t.row([ 'Activity Class:', activity_class ])
      end
      # It's unlikely that anybody ever cares about the METmax value.
      #if (metmax = user_data.metmax)
      #  t.row([ 'METmax:', "#{metmax} MET" ])
      #end
      if (vo2max = @fit_activity.vo2max)
        t.row([ 'VO2max:', "#{'%.1f' % vo2max} ml/kg/min" ])
      end
      t
    end

  end

end

