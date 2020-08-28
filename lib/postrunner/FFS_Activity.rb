#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = FFS_Activity.rb -- PostRunner - Manage the data from your Garmin sport devices.
#
# Copyright (c) 2015, 2016 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'fit4ruby'
require 'perobs'

require 'postrunner/ActivitySummary'
require 'postrunner/DataSources'
require 'postrunner/EventList'
require 'postrunner/FlexiTable'
require 'postrunner/ActivityView'
require 'postrunner/Schema'
require 'postrunner/QueryResult'
require 'postrunner/DirUtils'

module PostRunner

  class Stop < Struct.new(:index, :start_time, :duration, :end_time, :speed, :distance, :leg_speed)
  end


  # The FFS_Activity objects can store a reference to the FIT file data and
  # caches some frequently used values. In some cases the cached values can be
  # used to overwrite the data from the FIT file.
  class FFS_Activity < PEROBS::Object

    include DirUtils
	include Fit4Ruby::Converters

    @@Schemata = {
      'long_date' => Schema.new('long_date', 'Date',
                                { :func => 'timestamp',
                                  :column_alignment => :left,
                                  :format => 'date_with_weekday' }),
      'sub_type' => Schema.new('sub_type', 'Subtype',
                               { :func => 'activity_sub_type',
                                 :column_alignment => :left }),
      'type' => Schema.new('type', 'Type',
                           { :func => 'activity_type',
                             :column_alignment => :left })
    }

    ActivityTypes = {
      'generic' => 'Generic',
      'running' => 'Running',
      'cycling' => 'Cycling',
      'transition' => 'Transition',
      'fitness_equipment' => 'Fitness Equipment',
      'swimming' => 'Swimming',
      'basketball' => 'Basketball',
      'soccer' => 'Soccer',
      'tennis' => 'Tennis',
      'american_football' => 'American Football',
      'walking' => 'Walking',
      'cross_country_skiing' => 'Cross Country Skiing',
      'alpine_skiing' => 'Alpine Skiing',
      'snowboarding' => 'Snowboarding',
      'rowing' => 'Rowing',
      'mountaineering' => 'Mountaneering',
      'hiking' => 'Hiking',
      'multisport' => 'Multisport',
      'paddling' => 'Paddling',
      'all' => 'All'
    }
    ActivitySubTypes = {
      'generic' => 'Generic',
      'treadmill' => 'Treadmill',
      'street' => 'Street',
      'trail' => 'Trail',
      'track' => 'Track',
      'spin' => 'Spin',
      'indoor_cycling' => 'Indoor Cycling',
      'road' => 'Road',
      'mountain' => 'Mountain',
      'downhill' => 'Downhill',
      'recumbent' => 'Recumbent',
      'cyclocross' => 'Cyclocross',
      'hand_cycling' => 'Hand Cycling',
      'track_cycling' => 'Track Cycling',
      'indoor_rowing' => 'Indoor Rowing',
      'elliptical' => 'Elliptical',
      'stair_climbing' => 'Stair Climbing',
      'lap_swimming' => 'Lap Swimming',
      'open_water' => 'Open Water',
      'flexibility_training' => 'Flexibility Training',
      'strength_training' => 'Strength Training',
      'warm_up' => 'Warm up',
      'match' => 'Match',
      'exercise' => 'Excersize',
      'challenge' => 'Challenge',
      'indoor_skiing' => 'Indoor Skiing',
      'cardio_training' => 'Cardio Training',
      'virtual_activity' => 'Virtual Activity',
      'all' => 'All'
    }

    attr_persist :device, :fit_file_name, :norecord, :name, :note, :sport,
      :sub_sport, :timestamp, :total_distance, :total_timer_time, :total_elapsed_time, 
	  :avg_speed, :timezone_store
	  
    attr_reader :fit_activity  # basically a pointer to the activity in a FIT file
                               # tends to work as a read-only version (i.e., changes made
                               # here are not saved to the physical file)

    # Create a new FFS_Activity object.
    # @param p [PEROBS::Handle] PEROBS handle
    # @param fit_file_name [String] The fully qualified file name of the FIT
    #        file to add
    # @param fit_entity [Fit4Ruby::FitEntity] The content of the loaded FIT
    #        file
    def initialize(p, device, fit_file_name, fit_entity)
      super(p)

      self.device = device
      self.fit_file_name = fit_file_name ? File.basename(fit_file_name) : nil
      self.name = fit_file_name ? File.basename(fit_file_name) : nil
      self.norecord = false

      if (@fit_activity = fit_entity)
        self.timestamp = fit_entity.timestamp
        self.total_timer_time = fit_entity.total_timer_time
		self.total_elapsed_time = fit_entity.sessions[0].total_elapsed_time
        self.sport = fit_entity.sport
        self.sub_sport = fit_entity.sub_sport
        self.total_distance = fit_entity.total_distance
        self.avg_speed = fit_entity.avg_speed
        if fit_entity.local_timestamp && fit_entity.timestamp
            self.timezone_store = (fit_entity.local_timestamp - fit_entity.timestamp) 
        else
            self.timezone_store = -4 * 3600  #default to eastern (daylight?)
        end
      end
    end

    # Store a copy of the given FIT file in the corresponding directory.
    # @param fit_file_name [String] Fully qualified name of the FIT file.
    def store_fit_file(fit_file_name)
      # Get the right target directory for this particular FIT file.
      dir = @store['file_store'].fit_file_dir(File.basename(fit_file_name),
                                              @device.long_uid, 'activity')
											  
      # Create the necessary directories if they don't exist yet.
      create_directory(dir, 'Device activity diretory')

      # Copy the file into the target directory.
      begin
        FileUtils.cp(fit_file_name, dir)
      rescue StandardError
        Log.fatal "Cannot copy #{fit_file_name} into #{dir}: #{$!}"
      end
    end

    # Copy the given FIT file to a new name in the same directory.
    # @param fit_file_name [String] File name of the FIT file.
    def copy_fit_file(new_fit_file_name)
      # Get the right target directory for this particular FIT file.
      dir = @store['file_store'].fit_file_dir(File.basename(@fit_file_name),
                                              @device.long_uid, 'activity')
											  
	  orig_fit_file = File.join(dir, @fit_file_name)
	  new_fit_file  = File.join(dir, new_fit_file_name)
	  
      # Create the necessary directories if they don't exist yet.
      create_directory(dir, 'Device activity diretory')

      # Copy the file into the target directory.
      begin
        FileUtils.cp(orig_fit_file, new_fit_file)
      rescue StandardError
        Log.fatal "Cannot copy #{@fit_file_name} to #{new_fit_file}: #{$!}"
      end
    end

    # FFS_Activity objects are sorted by their timestamp values and then by
    # their device long_uids.
    def <=>(a)
      @timestamp == a.timestamp ? a.device.long_uid <=> self.device.long_uid :
        a.timestamp <=> @timestamp
    end

    def check
      # total_elapsed_time updated in Fit4Ruby::Session(check)
	  load_fit_file
	  self.total_elapsed_time = @fit_activity.sessions[0].total_elapsed_time
	  generate_html_report
      Log.info "FIT file #{@fit_file_name} is OK"
    end

    def dump(filter)
      load_fit_file(filter)
    end

    def query(key)
      unless @@Schemata.include?(key)
        raise ArgumentError, "Unknown key '#{key}' requested in query"
      end

      schema = @@Schemata[key]

      if schema.func
        value = send(schema.func)
      else
        unless instance_variable_defined?(key)
          raise ArgumentError, "Don't know how to query '#{key}'"
        end
        value = instance_variable_get(key)
      end

      QueryResult.new(value, schema)
    end

    def events
      load_fit_file
      puts EventList.new(self, @store['config']['unit_system'].to_sym).to_s
    end

    def show
      html_file = html_file_name

      generate_html_report #unless File.exists?(html_file)

      @store['file_store'].show_in_browser(html_file)
    end
	
	# split files based at times where stopped duration >= duration (in hours)
	def split(duration)
	   stop_array = stops(duration*3600.0)
	   split_activities = []
	   start_slice = 0
	   fit_file_base_name = @fit_file_name.delete_suffix(".fit")
	   hold_records = @fit_activity.records
 
       last_ind = 0
	   stop_array.each_with_index do |stop, ind|
		 temp_fit_file_name = "#{fit_file_base_name}_#{ind}.fit"
		 #copy_fit_file(temp_fit_file_name)
		 #load_temp_fit_file(temp_fit_file_name)   # creates @temp_fit_activity
		 #@fit_activity.records.slice!(start_slice, stop.index - start_slice + 1)
		 test_records = @fit_activity.records[start_slice..stop.index]
		 @fit_activity.records = test_records
		 start_slice = stop.index+1
		 last_ind = ind+1
		 #do we need to write the file?
		 # Get the right target directory for this particular FIT file.
		 dir = @store['file_store'].fit_file_dir(File.basename(@fit_file_name),
                                              @device.long_uid, 'activity')
		 new_fit_file = File.join(dir, temp_fit_file_name)
		 Fit4Ruby.write(new_fit_file, @fit_activity)
		 #purge_temp_fit_file
		 # restore records
		 @fit_activity.records = hold_records
	   end
	   # handle the last segment
	   temp_fit_file_name = "#{fit_file_base_name}_#{last_ind}.fit"
	   test_records = @fit_activity.records[start_slice..@fit_activity.records.length]
	   @fit_activity.records = test_records
	   dir = @store['file_store'].fit_file_dir(File.basename(@fit_file_name),
                                              @device.long_uid, 'activity')
	   new_fit_file = File.join(dir, temp_fit_file_name)
	   Fit4Ruby.write(new_fit_file, @fit_activity)
	      	   
	end

    def sources
      load_fit_file
      puts DataSources.new(self, @store['config']['unit_system'].to_sym).to_s
    end

    # display information on stops > duration (in seconds)
        # if leg_speed = 0, then block is stopped
        # look for consectutive stopped blocks
        # for each consecutive stopped block
        # start time = 1st time in block
        # stopped time = sum of durations
        #
        # output:
        #
        # block    time      duration
        # 1		 0:10:30   0:00:30
        # 2	     1:45:22   0:10:00
        # 3		 2:20:12   0:00:05
    def stops(duration)
       stop_array = build_stops_table 
		
	   stop_array.select! { |stop_info| stop_info.duration >= duration }
       stop_array = update_leg_speed(stop_array)
	   
	   puts stops_to_s(stop_array)
	   
	   return stop_array
    end

    def update_leg_speed(stop_array)
       leg_start_dist = 0.0
       for ind in 0...stop_array.length do
           leg_dist = distance_act(stop_array[ind].start_time)*1000.0 - leg_start_dist  #meters
           ind > 0 ? leg_dur = stop_array[ind].start_time - stop_array[ind-1].end_time :
                     leg_dur = stop_array[ind].start_time - @fit_activity.records.first.timestamp  #seconds
           stop_array[ind].leg_speed = ( leg_dist / leg_dur.to_f ) * conversion_factor('m/s', 'mph')
		   leg_start_dist = distance_act(stop_array[ind].end_time)*1000.0
		   binding.pry   #jkk
       end
	   
	   return stop_array
    end
       
	
	def build_stops_table
	   load_fit_file unless @fit_activity
 
       last_ind = @fit_activity.records.length-1
	   
	   last_timestamp = @fit_activity.records[last_ind].timestamp
	   stop_array = []
	  
       @fit_activity.records.reverse.each_with_index do |record, ind|
         delta_t = last_timestamp - record.timestamp	
         #puts "#{ind}, #{record.speed}, #{delta_t}"
         if record.speed == 0 || record.speed.nil? || delta_t >=60  #jkk guess for now, but seems to work
			stop_array << Stop.new( last_ind-ind, record.timestamp, 
			             delta_t, last_timestamp, record.speed, 
						 distance_act(record.timestamp).round(1) )
	     end
		 last_timestamp = record.timestamp
       end  #record do loop
	   
	   stop_array.reverse!
	   
	   # need to combine sequential zero speed records and points in close proximity
	   ind = 1
	   until ind >= stop_array.length
	     if (stop_array[ind].index == stop_array[ind-1].index+1) || 
		       (stop_array[ind].start_time == stop_array[ind-1].end_time)  ||
			    (stop_array[ind].distance - stop_array[ind-1].distance).abs <= 0.3 
			#stop_array[ind-1].duration += stop_array[ind].duration
			stop_array[ind-1].end_time = stop_array[ind].end_time
			stop_array[ind-1].duration = stop_array[ind-1].end_time - stop_array[ind-1].start_time
			stop_array.slice!(ind)
		 else
			ind += 1
		 end
	   end

	   return stop_array
	end

	def stops_to_s(stop_array)
	  t = FlexiTable.new
      t.head
      t.row([ 'Index', 'Start time', 'Duration', 'End time', 'Dist', 'Leg Speed' ])
      t.set_column_attributes([
        { :halign => :right },
        { :halign => :right },
        { :halign => :right },
        { :halign => :right },
        { :halign => :right },
        { :halign => :right }
      ])
      t.body

      t.row([ 'Start', @fit_activity.records.first.timestamp.getlocal(@timezone_store).strftime("%_m/%e/%y %H:%M:%S"), '-', '-', '0 km', '-' ])

      stop_array.each do |stop_info|
        t.cell(stop_info.index)
        t.cell(stop_info.start_time.getlocal(@timezone_store).strftime("%_m/%e/%y %H:%M:%S"))
        t.cell(secsToHMS(stop_info.duration))
        t.cell(stop_info.end_time.getlocal(@timezone_store).strftime("%_m/%e/%y %H:%M:%S"))
        t.cell('%0.f km' % stop_info.distance)
        t.cell('%0.1f mph' % stop_info.leg_speed)
        t.new_row
      end
      last_leg_length = ( distance_act(@fit_activity.records.last.timestamp) - 
                          distance_act(stop_array.last.end_time) ) * 1000   #meters
      last_leg_dur = @fit_activity.records.last.timestamp - stop_array.last.end_time  #seconds
      last_leg_spd = ( last_leg_length / last_leg_dur ) * conversion_factor('m/s', 'mph')
      t.row([ 'Finish', 
              @fit_activity.records.last.timestamp.getlocal(@timezone_store).strftime("%_m/%e/%y %H:%M:%S"), 
              '-', 
              '-',
              '%0.f km' % distance_act(@fit_activity.records.last.timestamp),
              '%0.1f mph' % last_leg_spd  ])

      t
    end


    def summary
      load_fit_file
      puts ActivitySummary.new(self, @store['config']['unit_system'].to_sym,
                               { :name => @name,
                                 :type => activity_type,
                                 :sub_type => activity_sub_type }).to_s
    end

    def set(attribute, value)
      case attribute
      when 'name'
        self.name = value
      when 'note'
        self.note = value
      when 'type'
        load_fit_file
        unless ActivityTypes.values.include?(value)
          Log.fatal "Unknown activity type '#{value}'. Must be one of " +
                    ActivityTypes.values.join(', ')
        end
        self.sport = ActivityTypes.invert[value]
      when 'subtype'
        unless ActivitySubTypes.values.include?(value)
          Log.fatal "Unknown activity subtype '#{value}'. Must be one of " +
                    ActivitySubTypes.values.join(', ')
        end
        self.sub_sport = ActivitySubTypes.invert[value]
      when 'norecord'
        unless %w( true false).include?(value)
          Log.fatal "norecord must either be 'true' or 'false'"
        end
        self.norecord = value == 'true'
      else
        Log.fatal "Unknown activity attribute '#{attribute}'. Must be one of " +
                  'name, type or subtype'
      end
      generate_html_report
    end
	
	def set_timezone(offset)
		self.timezone_store = offset * 3600
	end
	
	def timezone
		return @timezone_store
	end

    # Return true if this activity generated any personal records.
    def has_records?
      !@store['records'].activity_records(self).empty?
    end

    def html_file_name(full_path = true)
      fn = "#{@device.short_uid}_#{@fit_file_name[0..-5]}.html"
      full_path ? File.join(@store['config']['html_dir'], fn) : fn
    end

    def generate_html_report
      load_fit_file
      ActivityView.new(self, @store['config']['unit_system'].to_sym)
    end

    def activity_type
      ActivityTypes[@sport] || 'Undefined'
    end

    def activity_sub_type
      ActivitySubTypes[@sub_sport] || "Undefined #{@sub_sport}"
    end

    def distance(timestamp, unit_system)
      load_fit_file

      @fit_activity.records.each do |record|
        if record.timestamp >= timestamp
          unit = { :metric => 'km', :statute => 'mi'}[unit_system]
          value = record.get_as('distance', unit)
          return '-' unless value
          return "#{'%0.2f %s' % [value, unit]}"
        end
      end

      '-'
    end
	
	def distance_act(timestamp)
      load_fit_file

      unit = 'km'  #{ :metric => 'km', :statute => 'mi'}[unit_system]

      @fit_activity.records.each do |record|
        if record.timestamp >= timestamp
          value = record.get_as('distance', unit)
          return nil unless value
          return value
        end
      end

      return nil
    end

    def load_fit_file(filter = nil)
      return if @fit_activity

      dir = @store['file_store'].fit_file_dir(@fit_file_name,
                                              @device.long_uid, 'activity')
      fit_file = File.join(dir, @fit_file_name)
      begin
        @fit_activity = Fit4Ruby.read(fit_file, filter)
      rescue Fit4Ruby::Error
        Log.fatal "#{@fit_file_name} corrupted: #{$!}"
      end

      unless @fit_activity
        Log.fatal "#{fit_file} does not contain any activity records"
      end
    end

    def purge_fit_file
      @fit_activity = nil
    end

	def load_temp_fit_file(fit_file_name, filter = nil)
	  return if @temp_fit_activity
      dir = @store['file_store'].fit_file_dir(@fit_file_name,
                                              @device.long_uid, 'activity')
      fit_file = File.join(dir, fit_file_name)
      begin
        @temp_fit_activity = Fit4Ruby.read(fit_file, filter)
      rescue Fit4Ruby::Error
        Log.fatal "#{fit_file_name} corrupted: #{$!}"
      end

      unless @fit_activity
        Log.fatal "#{fit_file} does not contain any activity records"
      end
    end
	  
    def purge_temp_fit_file
      @temp_fit_activity = nil
    end
	  


  end

end

