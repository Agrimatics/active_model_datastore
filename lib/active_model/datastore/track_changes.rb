module ActiveModel::Datastore
  module TrackChanges
    extend ActiveSupport::Concern

    included do
      attr_accessor :exclude_from_save
    end

    def tracked_attributes
      []
    end

    ##
    # Resets the ActiveModel::Dirty tracked changes.
    #
    def reload!
      clear_changes_information
      self.exclude_from_save = false
    end

    def exclude_from_save?
      @exclude_from_save.nil? ? false : @exclude_from_save
    end

    ##
    # Determines if any attribute values have changed using ActiveModel::Dirty.
    # For attributes enabled for change tracking compares changed values. All values
    # submitted from an HTML form are strings, thus a string of 25.0 doesn't match an
    # original float of 25.0. Call this method after valid? to allow for any type coercing
    # occurring before saving to datastore.
    #
    # Consider the scenario in which the user submits an unchanged form value named `area`.
    # The initial value from datastore is a float of 25.0, which during assign_attributes
    # is set to a string of '25.0'. It is then coerced back to a float of 25.0 during a
    # validation callback. The area_changed? will return true, yet the value is back where
    # is started.
    #
    # For example:
    #
    #   class Shapes
    #     include ActiveModel::Datastore
    #
    #     attr_accessor :area
    #     enable_change_tracking :area
    #     after_validation :format_values
    #
    #     def format_values
    #       format_property_value :area, :float
    #     end
    #
    #     def update(params)
    #       assign_attributes(params)
    #       if valid?
    #         puts values_changed?
    #         puts area_changed?
    #         p area_change
    #       end
    #     end
    #   end
    #
    # Will result in this:
    #   values_changed? false
    #   area_changed? true # This is correct, as area was changed but the value is identical.
    #   area_change [0, 0]
    #
    # If none of the tracked attributes have changed, the `exclude_from_save` attribute is
    # set to true and the method returns false.
    #
    def values_changed?
      unless tracked_attributes.present?
        raise TrackChangesError, 'Object has not been configured for change tracking.'
      end

      changed = marked_for_destruction? ? true : false
      tracked_attributes.each do |attr|
        break if changed

        changed = send(attr) != send("#{attr}_was") if send("#{attr}_changed?")
      end
      self.exclude_from_save = !changed
      changed
    end

    def remove_unmodified_children
      return unless tracked_attributes.present? && nested_attributes?

      nested_attributes.each do |attr|
        with_changes = Array(send(attr.to_sym)).select(&:values_changed?)
        send("#{attr}=", with_changes)
      end
      nested_attributes.delete_if { |attr| Array(send(attr.to_sym)).empty? }
    end

    module ClassMethods
      ##
      # Enables track changes functionality for the provided attributes using ActiveModel::Dirty.
      #
      # Calls define_attribute_methods for each attribute provided.
      #
      # Creates a setter for each attribute that will look something like this:
      #   def name=(value)
      #     name_will_change! unless value == @name
      #     @name = value
      #   end
      #
      # Overrides tracked_attributes to return an Array of the attributes configured for tracking.
      #
      def enable_change_tracking(*attributes)
        attributes = attributes.collect(&:to_sym)
        attributes.each do |attr|
          define_attribute_methods attr

          define_method("#{attr}=") do |value|
            send("#{attr}_will_change!") unless value == instance_variable_get("@#{attr}")
            instance_variable_set("@#{attr}", value)
          end
        end

        define_method('tracked_attributes') { attributes }
      end
    end
  end
end
