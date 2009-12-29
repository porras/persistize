module Persistize
  module ClassMethods
    def persistize(*args)
      options = args.pop if args.last.is_a?(Hash)
      
      args.each do |method|
        attribute = method.to_s.sub(/\?$/, '')
        
        original_method = :"_unpersistized_#{attribute}"
        update_method   = :"_update_#{attribute}"
        
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          alias #{original_method} #{method}                # alias _unpersistized_full_name full_name
                                                            # 
          def #{method}                                     # def full_name
            if new_record?                                  #   if new_record?
              #{original_method}                            #     _unpersistized_full_name
            else                                            #   else
              self[:#{attribute}]                           #     self[:full_name]
            end                                             #   end
          end                                               # end
                                                            # 
          before_save :#{update_method}                     # before_save :_update_full_name
                                                            # 
          def #{update_method}                              # def _update_full_name
            self[:#{attribute}] = #{original_method}        #   self[:full_name] = _unpersistized_full_name
            true # return true to avoid canceling the save  #   true
          end                                               # end
                                                            # 
          def #{update_method}!                             # def _update_full_name!
            #{update_method}                                #   _update_full_name
            save! if #{attribute}_changed?                  #   save! if full_name_changed?
          end                                               # end
        RUBY

        if options && options[:depending_on]
          dependencies = [options[:depending_on]].flatten
          
          dependencies.each do |dependency|
            generate_callback(reflections[dependency], update_method)
          end
        end
        
      end
    end
    
    private
    
    def generate_callback(association, update_method)
      callback_name = :"#{update_method}_in_#{self.to_s.underscore}_callback"
      association_type = "#{association.macro}#{'_through' if association.through_reflection}"
      generate_method = :"generate_#{association_type}_callback"
      unless respond_to?(generate_method, true)
        raise "#{association_type} associations are not supported by persistize" 
      end
      send(generate_method, association, update_method, callback_name)
    end
    
    def generate_has_many_callback(association, update_method, callback_name)
      association.klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{callback_name}                                                     # def _update_completed_in_project_callback
          return true unless parent_id = self[:#{association.primary_key_name}]  #   return true unless parent_id = self[:project_id]
          parent = #{self.name}.find(parent_id)                                  #   parent = Project.find(parent_id)
          parent.#{update_method}!                                               #   parent._update_completed!
        end                                                                      # end
        after_save :#{callback_name}                                             # after_save :_update_completed_in_project_callback
        after_destroy :#{callback_name}                                          # after_destroy :_update_completed_in_project_callback
      RUBY
    end
    
    def generate_has_many_through_callback(association, update_method, callback_name)                         
      association.klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{callback_name}                                                                                # def _update_completed_in_person_callback
          return true unless through_id = self[:#{association.through_reflection.association_foreign_key}]  #   return true unless through_id = self[:project_id]
          through = #{association.through_reflection.class_name}.find(through_id)                           #   through = Project.find(through_id)                         
          return true unless parent_id = through[:#{association.primary_key_name}]                          #   return true unless parent_id = self[:person_id]
          parent = #{self.name}.find(parent_id)                                                             #   parent = Person.find(person_id)
          parent.#{update_method}!                                                                          #   parent._update_completed!
        end                                                                                                 # end
        after_save :#{callback_name}                                                                        # after_save :_update_completed_in_person_callback
        after_destroy :#{callback_name}                                                                     # after_destroy :_update_completed_in_person_callback
      RUBY
    end
    
    def generate_belongs_to_callback(association, update_method, callback_name)
      association.klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{callback_name}                                                                  # def _update_project_name_in_task_callback
          childs = #{self.name}.all(:conditions => {:#{association.primary_key_name} => id})  #   childs = Task.all(:conditions => {:project_id => id})
          childs.each(&:"#{update_method}!")                                                  #   childs.each(&:"_update_project_name!")
        end                                                                                   # end
        after_save :#{callback_name}                                                          # after_save :_update_project_name_in_task_callback
        after_destroy :#{callback_name}                                                       # after_destroy :_update_project_name_in_task_callback
      RUBY
    end
  
  end
end

ActiveRecord::Base.extend(Persistize::ClassMethods)