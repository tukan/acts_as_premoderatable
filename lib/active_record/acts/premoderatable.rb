module ActiveRecord
  module Acts
    module Premoderatable
      
      def self.included(base)
        base.extend(ClassMethods)        
      end
      
      module ClassMethods
        def acts_as_premoderatable(options = {})          
          status_column = options[:status_column] || 'status'
          
          acts_as_state_machine :initial => :draft, :column => status_column          
                  
          attr_protected :deleted_at, :published_at, :status, :status_changed_at

          named_scope :not_deleted, :conditions =>  "#{self.class.state_column} != 'deleted'" 
          named_scope :published, :conditions =>  "#{self.class.state_column} = 'approved'" 
          named_scope :unpublished, :conditions => "#{self.class.state_column} != 'approved'"
          named_scope :recent, lambda{ {:conditions => ["published_at >= ?", Time.now.beginning_of_day]}}
          
          
          named_scope :deleted, :conditions => { "#{self.class.state_column }= 'deleted'" }
          named_scope :draft, :conditions => { "#{self.class.state_column} = 'draft'" }
          named_scope :pending, :conditions => { "#{self.class.state_column} = 'pending'" }
          named_scope :declined, :conditions => { "#{self.class.state_column} = 'declined'" }
          named_scope :approved, :conditions => { "#{self.class.state_column} = 'approved'" }

          named_scope :recent, lambda{ {:conditions => ["published_at >= ?", Time.now.beginning_of_day]}}
          
          define_callbacks :after_publish, :after_unpublish, :after_acts_as_publishable
          
          state :draft, :enter => Proc.new {|o| o.status_changed_at = Time.now }
          state :pending, :enter => Proc.new {|o| o.status_changed_at = Time.now }
          state :declined, :enter => Proc.new {|o| o.status_changed_at = Time.now }
          state :approved, :enter => Proc.new {|o| o.published_at = Time.now; o.status_changed_at = Time.now; o.send_later(:update_user_stats, :unpublished => -1, :published => +1, :faved => +1) }
          state :deleted, :enter => Proc.new {|o| o.deleted_at = Time.now; o.status_changed_at = Time.now; o.send_later(:update_user_stats, :unpublished => +1, :published => -1, :faved => -1) }
          
          event :draft do
            transitions :from => :draft, :to => :draft
            transitions :from => :pending, :to => :draft
            transitions :from => :declined, :to => :draft
            transitions :from => :approved, :to => :draft
          end
          
          event :delete do 
            transitions :from => :draft, :to => :deleted
            transitions :from => :pending, :to => :deleted
            transitions :from => :declined, :to => :deleted
            transitions :from => :approved, :to => :deleted
          end  
          
          event :approve do
            transitions :from => :draft, :to => :approved
            transitions :from => :pending, :to => :approved
            transitions :from => :declined, :to => :approved
          end
          
          event :decline do
            transitions :from => :pending, :to => :declined
            transitions :from => :approved, :to => :declined
          end
              
          include ActiveRecord::Acts::Premoderatable::InstanceMethods
        end
      end
      
      module InstanceMethods
        def is_published
          self.approved?
        end
        
        def is_published?
          self.approved?
        end
        
        def publish!(user)
          if self.draft?
            if self.can_approve?(user) 
              self.approve!
              callback :after_publish 
              callback :after_acts_as_publishable
            else
              self.pending!
            end  
          elsif self.pending?
            if self.can_approve?(user)
              self.approve!
              callback :after_publish 
              callback :after_acts_as_publishable
            else 
              self.pending!
            end
          elsif self.approve?
            if self.can_approve?(user)
              self.approve!
              callback :after_publish
              callback :after_acts_as_publishable
            else
              self.pending!
            end
          elsif self.declined?
            if self.can_approve?(user)
              self.approve!
              callback :after_publish
              callback :after_acts_as_publishable
            else
              self.pending!
            end
          end  
        end  

        def unpublish!(user)
          if self.approved?
            self.can_decline?(user) ? self.decline! : self.draft!
            callback(:after_unpublish)
            callback(:after_acts_as_publishable)
          elsif self.pending?
            self.can_decline?(user) ? self.decline! : self.draft!
            callback(:after_unpublish)
            callback(:after_acts_as_publishable)
          elsif self.declined?
            self.draft!
            callback(:after_unpublish)
            callback(:after_acts_as_publishable)
          end
        end
              
      end        
    end
  end
end


