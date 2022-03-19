module Ladb::OpenCutList

  require_relative '../lib/kuix/kuix'
  require_relative '../utils/path_utils'
  require_relative '../helper/screen_scale_factor_helper'
  require_relative '../helper/layer_visibility_helper'
  require_relative '../model/attributes/material_attributes'

  class SmartPaintTool < Kuix::KuixTool

    include ScreenScaleFactorHelper
    include LayerVisibilityHelper

    ACTION_PAINT_FACE = 0
    ACTION_PAINT_PART = 1
    ACTION_UNPAINT_FACE = 2
    ACTION_UNPAINT_PART = 3
    ACTION_PICK = 4

    ACTIONS = [
      ACTION_PAINT_FACE,
      ACTION_PAINT_PART,
      ACTION_UNPAINT_FACE,
      ACTION_UNPAINT_PART,
      ACTION_PICK
    ]

    COLOR_MATERIAL_TYPES = {
      0 => Sketchup::Color.new(128, 128, 128, 255).freeze,
      1 => Sketchup::Color.new(76, 175, 80, 255).freeze,
      2 => Sketchup::Color.new(237, 162, 0, 255).freeze,
      3 => Sketchup::Color.new(245, 89, 172, 255).freeze,
      4 => Sketchup::Color.new(102, 142, 238, 255).freeze,
      5 => Sketchup::Color.new(0, 0, 0, 255).freeze
    }

    @@current_material = nil
    @@material_type_filters = nil
    @@action = nil

    def initialize
      super

      model = Sketchup.active_model
      if model

        # Force global current material to be valid
        unless @@current_material.nil?
          begin
            @@current_material.model == model
          rescue => e # Reference to deleted Entity
            @@current_material = nil
          end
        end

        @paint_color = nil
        @unpaint_color = nil

        @selected_button = nil

        # Create cursors
        @cursor_paint_face_id = create_cursor('paint-face', 7, 25)
        @cursor_paint_part_id = create_cursor('paint-part', 7, 25)
        @cursor_unpaint_id = create_cursor('unpaint', 7, 25)
        @cursor_picker_id = create_cursor('picker', 7, 25)
        @cursor_nopaint_id = create_cursor('nopaint', 7, 25)

        _populate_material_defs(model)

      end

    end

    def setup_widgets(view)

      @canvas.layout = Kuix::BorderLayout.new

      @unit = [ [ view.vpheight / 150, 10 ].min, _screen_scale(4) ].max

      panel = Kuix::Widget.new
      panel.layout_data = Kuix::BorderLayoutData.new(Kuix::BorderLayoutData::SOUTH)
      panel.layout = Kuix::BorderLayout.new
      @canvas.append(panel)

        # Status panel

        @status = Kuix::Widget.new
        @status.layout_data = Kuix::BorderLayoutData.new(Kuix::BorderLayoutData::NORTH)
        @status.layout = Kuix::InlineLayout.new(true, 0, Kuix::Anchor.new(Kuix::Anchor::CENTER))
        @status.padding.set_all(@unit)
        @status.visible = false
        @status.set_style_attribute(:background_color, Sketchup::Color.new(255, 255, 255, 128))
        panel.append(@status)

          @status_lbl_1 = Kuix::Label.new
          @status_lbl_1.text_size = @unit * 3
          @status.append(@status_lbl_1)

          @status_lbl_2 = Kuix::Label.new
          @status_lbl_2.text_size = @unit * 2
          @status.append(@status_lbl_2)

        # Settings panel

        @settings = Kuix::Widget.new
        @settings.layout_data = Kuix::BorderLayoutData.new(Kuix::BorderLayoutData::SOUTH)
        @settings.layout = Kuix::GridLayout.new(1, 2, 0, @unit)
        @settings.border.set(@unit / 2)
        @settings.padding.set_all(@unit * 2)
        @settings.set_style_attribute(:background_color, Sketchup::Color.new('white'))
        @settings.set_style_attribute(:border_color, Sketchup::Color.new(200, 200, 200, 255))
        @settings.visible = false
        panel.append(@settings)

          filters = Kuix::Widget.new
          filters.layout = Kuix::GridLayout.new(COLOR_MATERIAL_TYPES.length + 1,1, @unit, @unit)
          @settings.append(filters)

            filters_lbl = Kuix::Label.new
            filters_lbl.text = Plugin.instance.get_i18n_string('tool.smart_paint.filters').upcase
            filters_lbl.text_size = @unit * 3
            filters_lbl.text_bold = true
            filters.append(filters_lbl)

            @filter_buttons = []
            for type in 0..(COLOR_MATERIAL_TYPES.length - 1)

              filters_btn = Kuix::Button.new
              filters_btn.layout = Kuix::GridLayout.new
              filters_btn.min_size.set_all(@unit * 10)
              filters_btn.border.set_all(@unit)
              filters_btn.set_style_attribute(:background_color, Sketchup::Color.new('white'))
              filters_btn.set_style_attribute(:background_color, COLOR_MATERIAL_TYPES[type], :active)
              filters_btn.set_style_attribute(:background_color, COLOR_MATERIAL_TYPES[type].blend(Sketchup::Color.new('white'), 0.2), :hover)
              filters_btn.set_style_attribute(:border_color, COLOR_MATERIAL_TYPES[type], :selected)
              filters_btn.selected = @@material_type_filters[type]
              filters_btn.data = type
              filters_btn.append_static_label(Plugin.instance.get_i18n_string("tool.smart_paint.filter_#{type}"), @unit * 3)
              filters_btn.on(:click) { |button|

                toggle_filter_by_type(button.data)

                # Re populate material defs & setup corresponding buttons
                _populate_material_defs(view.model)
                _setup_material_buttons

              }
              filters_btn.on(:doubleclick) { |button|

                set_filters(false)
                set_filter_by_type(button.data, true)

                # Re populate material defs & setup corresponding buttons
                _populate_material_defs(view.model)
                _setup_material_buttons

              }
              filters.append(filters_btn)

              @filter_buttons.push(filters_btn)

            end

          actions = Kuix::Widget.new
          actions.layout = Kuix::GridLayout.new(COLOR_MATERIAL_TYPES.length + 1,1, @unit, @unit)
          @settings.append(actions)

            actions_lbl = Kuix::Label.new
            actions_lbl.text = Plugin.instance.get_i18n_string('tool.smart_paint.action').upcase
            actions_lbl.text_size = @unit * 3
            actions_lbl.text_bold = true
            actions.append(actions_lbl)

            @action_buttons = []
            ACTIONS.each { |action|

              actions_btn = Kuix::Button.new
              actions_btn.layout = Kuix::GridLayout.new
              actions_btn.min_size.set_all(@unit * 10)
              actions_btn.border.set_all(@unit)
              actions_btn.set_style_attribute(:background_color, Sketchup::Color.new('white'))
              actions_btn.set_style_attribute(:background_color, Sketchup::Color.new(200, 200, 200, 255), :active)
              actions_btn.set_style_attribute(:background_color, Sketchup::Color.new(200, 200, 200, 255).blend(Sketchup::Color.new('white'), 0.2), :hover)
              actions_btn.set_style_attribute(:border_color, Sketchup::Color.new(200, 200, 200, 255), :selected)
              actions_btn.selected = @@action == action
              actions_btn.data = action
              actions_btn.append_static_label(Plugin.instance.get_i18n_string("tool.smart_paint.action_#{action}"), @unit * 3)
              actions_btn.on(:click) { |button|
                set_action(action)
              }
              actions.append(actions_btn)

              @action_buttons.push(actions_btn)

          }

        west = Kuix::Widget.new
        west.layout_data = Kuix::BorderLayoutData.new(Kuix::BorderLayoutData::WEST)
        west.layout = Kuix::GridLayout.new
        west.padding.set(@unit, @unit / 2, @unit, @unit)
        west.set_style_attribute(:background_color, Sketchup::Color.new('white'))
        panel.append(west)

          west_btn = Kuix::Button.new
          west_btn.layout = Kuix::GridLayout.new
          west_btn.min_size.set_all(@unit * 10)
          west_btn.border.set_all(@unit)
          west_btn.set_style_attribute(:background_color, Sketchup::Color.new(200, 200, 200, 255))
          west_btn.set_style_attribute(:background_color, Sketchup::Color.new(220, 220, 220, 255), :active)
          west_btn.set_style_attribute(:border_color, Sketchup::Color.new(128, 128, 128, 255), :hover)
          west_btn.append_static_label('⚙︎', @unit * 5)
          west_btn.on(:click) { |button|
            @settings.visible = !@settings.visible?
          }
          west.append(west_btn)

        east = Kuix::Widget.new
        east.layout_data = Kuix::BorderLayoutData.new(Kuix::BorderLayoutData::EAST)
        east.layout = Kuix::GridLayout.new
        east.padding.set(@unit, @unit, @unit, @unit / 2)
        east.set_style_attribute(:background_color, Sketchup::Color.new('white'))
        panel.append(east)

          east_btn = Kuix::Button.new
          east_btn.layout = Kuix::GridLayout.new
          east_btn.min_size.set_all(@unit * 10)
          east_btn.border.set_all(@unit)
          east_btn.set_style_attribute(:background_color, Sketchup::Color.new(200, 200, 200, 255))
          east_btn.set_style_attribute(:background_color, Sketchup::Color.new(220, 220, 220, 255), :active)
          east_btn.set_style_attribute(:border_color, Sketchup::Color.new(128, 128, 128, 255), :hover)
          east_btn.append_static_label('+', @unit * 5)
          east_btn.on(:click) { |button|
            Plugin.instance.execute_dialog_command_on_tab('materials', 'new_material')
          }
          east.append(east_btn)

        # Buttons panel

        @btns = Kuix::Widget.new
        @btns.layout_data = Kuix::BorderLayoutData.new(Kuix::BorderLayoutData::CENTER)
        @btns.padding.set(@unit, 0, @unit, 0)
        @btns.set_style_attribute(:background_color, Sketchup::Color.new('white'))
        panel.append(@btns)

          _setup_material_buttons

    end

    # -- Setter --

    def set_action(action)

      @@action = action

      if @action_buttons
        @action_buttons.each { |button|
          button.selected = button.data == action
        }
      end

      # Update root cursor
      case action
      when ACTION_PAINT_FACE
        Sketchup.set_status_text(
          Plugin.instance.get_i18n_string('tool.smart_paint.status_paint_face') +
            ' | ' + Plugin.instance.get_i18n_string("tool.smart_paint.copy_key_#{Plugin.instance.platform_name}") + ' = ' + Plugin.instance.get_i18n_string('tool.smart_paint.status_unpaint_face') +
            ' | ' + Plugin.instance.get_i18n_string("tool.smart_paint.alt_key_#{Plugin.instance.platform_name}") + ' = ' + Plugin.instance.get_i18n_string('tool.smart_paint.status_pick'),
          SB_PROMPT)
        set_root_cursor(@cursor_paint_face_id)
      when ACTION_PAINT_PART
        Sketchup.set_status_text(
          Plugin.instance.get_i18n_string('tool.smart_paint.status_paint_part') +
            ' | ' + Plugin.instance.get_i18n_string("tool.smart_paint.copy_key_#{Plugin.instance.platform_name}") + ' = ' + Plugin.instance.get_i18n_string('tool.smart_paint.status_unpaint_part') +
            ' | ' + Plugin.instance.get_i18n_string("tool.smart_paint.alt_key_#{Plugin.instance.platform_name}") + ' = ' + Plugin.instance.get_i18n_string('tool.smart_paint.status_pick'),
          SB_PROMPT)
        set_root_cursor(@cursor_paint_part_id)
      when ACTION_UNPAINT_FACE
        Sketchup.set_status_text(Plugin.instance.get_i18n_string('tool.smart_paint.status_unpaint_face'), SB_PROMPT)
        set_root_cursor(@cursor_unpaint_id)
      when ACTION_UNPAINT_PART
        Sketchup.set_status_text(Plugin.instance.get_i18n_string('tool.smart_paint.status_unpaint_part'), SB_PROMPT)
        set_root_cursor(@cursor_unpaint_id)
      when ACTION_PICK
        Sketchup.set_status_text(Plugin.instance.get_i18n_string('tool.smart_paint.status_pick'), SB_PROMPT)
        set_root_cursor(@cursor_picker_id)
      else
        Sketchup.set_status_text('', SB_PROMPT)
        set_root_cursor(@cursor_nopaint_id)
      end

    end

    def is_action_face
      @@action == ACTION_PAINT_FACE || @@action == ACTION_UNPAINT_FACE
    end

    def is_action_part
      @@action == ACTION_PAINT_PART || @@action == ACTION_UNPAINT_PART
    end

    def is_action_paint
      @@action == ACTION_PAINT_FACE || @@action == ACTION_PAINT_PART
    end

    def is_action_unpaint
      @@action == ACTION_UNPAINT_FACE || @@action == ACTION_UNPAINT_PART
    end

    def is_action_pick
      @@action == ACTION_PICK
    end

    def set_filters(value = true)

      @@material_type_filters.keys.each do |type|
        set_filter_by_type(type, value)
      end

    end

    def set_filter_by_type(type, value)

      @@material_type_filters[type] = value

      if @filter_buttons
        @filter_buttons.each { |button|
          if button.data == type
            button.selected = value
          end
        }
      end

    end

    def toggle_filter_by_type(type)
      set_filter_by_type(type, !@@material_type_filters[type])
    end

    def set_current_material(material, material_attributes, update_buttons = false)

      # Save material as current
      @@current_material = material

      # Update the paint color
      @paint_color = material ? material.color.blend(Sketchup::Color.new(255, 255, 255), 0.85) : nil

      # Select the pick strategy
      if material_attributes

        # Set pick strategy according to material type
        case material_attributes.type
        when MaterialAttributes::TYPE_EDGE
          set_action(ACTION_PAINT_FACE)
        else
          set_action(ACTION_PAINT_PART)
        end

      else
        set_action(ACTION_PAINT_PART)
      end

      # Update buttons
      if update_buttons
        @material_buttons.each { |button|
          button.selected = button.data == material
        }
      end

    end

    def get_current_material
      @@current_material
    end

    # -- Tool stuff --

    def draw(view)

     if is_action_paint
       color = @paint_color
     elsif is_action_unpaint
       color = @unpaint_color
     else
       color = nil
     end
      if color && @triangles
        view.drawing_color = color
        view.draw(GL_TRIANGLES, @triangles)
      end

      super
    end

    # -- Events --

    def onActivate(view)
      super

      # Retrive pick helper
      @pick_helper = view.pick_helper

      # Observe materials events
      view.model.materials.add_observer(self)

    end

    def onDeactivate(view)
      super

      # Stop observing materials events
      view.model.materials.remove_observer(self)

    end

    def onKeyDown(key, repeat, flags, view)
      return if super
      if key == COPY_MODIFIER_KEY
        set_action(is_action_face ? ACTION_UNPAINT_FACE : ACTION_UNPAINT_PART)
        view.invalidate
      elsif key == ALT_MODIFIER_KEY
        @picked_path = nil
        set_action(ACTION_PICK)
        view.invalidate
      end
    end

    def onKeyUp(key, repeat, flags, view)
      return if super
      if key == COPY_MODIFIER_KEY || key == ALT_MODIFIER_KEY
        set_current_material(@@current_material, MaterialAttributes.new(@@current_material))
        view.invalidate
      end
    end

    def onLButtonUp(flags, x, y, view)
      return if super
      _pick_entity(x, y, view)
      if @picked_entity
        if is_action_paint
          @picked_entity.material = get_current_material
          return
        elsif is_action_unpaint
          @picked_entity.material = nil
          return
        end
      elsif @picked_path && is_action_pick
        material = _get_material_from_path(@picked_path)
        set_current_material(material, MaterialAttributes.new(material), true)
        return
      end
      UI.beep
    end

    def onMouseMove(flags, x, y, view)
      if super
        _reset(view)
        return
      end
      if get_current_material
        _pick_entity(x, y, view)
      end
    end

    def onMouseLeave(view)
      return if super
      _reset(view)
    end

    def onMaterialAdd(materials, material)
      _populate_material_defs(Sketchup.active_model)
      _setup_material_buttons
    end

    def onMaterialRemove(materials, material)
      if material == @@current_material
        @@current_material = nil
      end
      _populate_material_defs(Sketchup.active_model)
      _setup_material_buttons
    end

    def onMaterialChange(materials, material)
      _populate_material_defs(Sketchup.active_model)
      _setup_material_buttons
    end

    private

    def _populate_material_defs(model)

      # Setup default filter if not set
      if @@material_type_filters.nil?
        @@material_type_filters = {}
        for type in 0..COLOR_MATERIAL_TYPES.length - 1
          @@material_type_filters[type] = true
        end
      end

      # Build the material defs
      @material_defs = []
      current_material_exists = false
      model.materials.each do |material|
        material_attributes = MaterialAttributes.new(material)
        if @@material_type_filters[material_attributes.type]
          @material_defs.push({
                                :material => material,
                                :material_attributes => material_attributes
                              })
          if @@current_material.nil? && material == model.materials.current
            set_current_material(material, material_attributes)
          end
        end
        current_material_exists = current_material_exists || @@current_material == material
      end

      # Sort material defs (type > name)
      @material_defs.sort_by! { |material_def| [ MaterialAttributes::type_order(material_def[:material_attributes].type), material_def[:material].display_name ] }

      # Select default current material if necessary
      if model.materials.length == 0
        set_current_material(nil, nil)
      elsif @@current_material && !current_material_exists || @@current_material.nil? && !@material_defs.empty?
        set_current_material(@material_defs.first[:material], @material_defs.first[:material_attributes])
      else
        set_current_material(@@current_material, @@current_material ? MaterialAttributes.new(@@current_material) : nil)  # Reapply current material to setup the paint color
      end

    end

    def _setup_material_buttons

      @btns.remove_all
      @btns.layout = Kuix::GridLayout.new([ @material_defs.length, 10 ].min, (@material_defs.length / 10.0).ceil, @unit / 2, @unit / 2)

      if @material_defs.empty?

        warning_lbl = Kuix::Label.new
        warning_lbl.text = Plugin.instance.get_i18n_string("tool.smart_paint.warning.#{Sketchup.active_model.materials.length == 0 ? 'no_material' : 'all_filtered'}")
        warning_lbl.text_size = @unit * 3
        warning_lbl.margin.set_all(@unit)
        warning_lbl.set_style_attribute(:background_color, Sketchup::Color.new(242, 222, 222, 255))
        warning_lbl.set_style_attribute(:color, Sketchup::Color.new(169, 68, 66, 255))
        @btns.append(warning_lbl)

        if Sketchup.active_model.materials.length > 0
          @settings.visible = true
        end

      end

      @material_buttons = []
      @material_defs.each do |material_def|

        material = material_def[:material]
        material_attributes = material_def[:material_attributes]
        material_color_is_dark = (0.2126 * material.color.red + 0.7152 * material.color.green + 0.0722 * material.color.blue) <= 128

        btn = Kuix::Button.new
        btn.layout = Kuix::StaticLayout.new
        btn.min_size.set(@unit * 20, @unit * 10)
        btn.border.set_all(@unit)
        btn.set_style_attribute(:background_color, material.color)
        btn.set_style_attribute(:background_color, material.color.blend(Sketchup::Color.new(material_color_is_dark ? 'white' : 'black'), 0.7), :active)
        btn.set_style_attribute(:border_color, material.color.blend(Sketchup::Color.new(material_color_is_dark ? 'white' : 'black'), 0.7), :hover)
        btn.set_style_attribute(:border_color, Sketchup::Color.new('blue'), :selected)
        btn.append_static_label(material.display_name, @unit * 3, material_color_is_dark ? Sketchup::Color.new('white') : nil)
        btn.data = material
        btn.selected = material == get_current_material
        btn.on(:click) { |button|

          # Set material as current
          set_current_material(material, material_attributes, true)

        }
        btn.on(:enter) { |button|
          @status.visible = true
          @status_lbl_1.text = material.display_name
          @status_lbl_2.text = (material_attributes.type > 0 ? " (#{Plugin.instance.get_i18n_string("tab.materials.type_#{material_attributes.type}")})" : '')
          @status_lbl_2.visible = material_attributes.type > 0
        }
        btn.on(:leave) { |button|
          @status.visible = false
        }
        @btns.append(btn)

        @material_buttons.push(btn)

        if material_attributes.type > 0

          btn_overlay = Kuix::Widget.new
          btn_overlay.layout_data = Kuix::StaticLayoutData.new(1.0, 0, @unit * 2, @unit * 2, Kuix::Anchor.new(Kuix::Anchor::TOP_RIGHT))
          btn_overlay.set_style_attribute(:background_color, COLOR_MATERIAL_TYPES[material_attributes.type])
          btn_overlay.set_style_attribute(:border_color, Sketchup::Color.new('white'))
          btn_overlay.border.set(0, 0, @unit / 2, @unit / 2)
          btn_overlay.hittable = false
          btn.append(btn_overlay)

        end

      end

    end

    def _reset(view)
      if @picked_entity
        @picked_path = nil
        @picked_entity = nil
        @triangles = nil
        view.invalidate
      end
    end

    def _get_material_from_path(path)
      entity = path.last
      material = nil
      if entity
        if entity.material
          material = entity.material
        elsif path.length > 0
          material = _get_material_from_path(path.slice(0, path.length - 1))
        end
      end
      material
    end

    def _get_color_from_path(path)
      material = _get_material_from_path(path)
      if material
        color = material.color
      else
        color = Sketchup::Color.new(255, 255, 255)
      end
      color
    end

    def _pick_entity(x, y, view)
      if @pick_helper.do_pick(x, y) > 0
        @pick_helper.count.times { |pick_path_index|

          picked_path = @pick_helper.path_at(pick_path_index)
          if picked_path == @picked_path
            return  # Previously detected path, stop process to optimize.
          end
          if picked_path && picked_path.last && picked_path.last.is_a?(Sketchup::Face)

            @picked_path = picked_path

            case @@action

            when ACTION_PAINT_FACE, ACTION_UNPAINT_FACE

              @picked_entity = picked_path.last
              @unpaint_color = _get_color_from_path(picked_path.slice(0, picked_path.length - 1))
              @triangles = _compute_face_triangles(view, picked_path.last, PathUtils::get_transformation(picked_path))

              view.invalidate
              return

            when ACTION_PAINT_PART, ACTION_UNPAINT_PART

              tmp_picked_path = picked_path.to_a
              picked_path.reverse_each { |entity|
                if entity.is_a?(Sketchup::ComponentInstance)

                  @picked_entity = entity
                  @unpaint_color = _get_color_from_path(picked_path.slice(0, picked_path.length - 1))
                  @triangles = _compute_children_faces_tirangles(view, entity.definition.entities, PathUtils::get_transformation(tmp_picked_path))

                  view.invalidate
                  return

                end

                tmp_picked_path.pop
              }

              @picked_entity = nil
              @unpaint_color = nil
              @triangles = nil
              return

            when ACTION_PICK

              @picked_entity = nil
              @unpaint_color = nil
              @triangles = nil
              return

            end

          end

        }
      end
      _reset(view)
    end

    def _offset_toward_camera(view, points)
      offset_direction = view.camera.direction.reverse!
      points.map { |point|
        point = point.position if point.respond_to?(:position)
        # Model.pixels_to_model converts argument to integers.
        size = view.pixels_to_model(2, point) * 0.01
        point.offset(offset_direction, size)
      }
    end

    def _transform_points(points, transformation)
      return false if transformation.nil?
      points.each { |point| point.transform!(transformation) }
      true
    end

    def _compute_children_faces_tirangles(view, entities, transformation = nil)
      triangles = []
      entities.each { |entity|
        next if entity.is_a?(Sketchup::Edge)   # Minor Speed improvement when there's a lot of edges
        if entity.visible? && _layer_visible?(entity.layer)
          if entity.is_a?(Sketchup::Face)
            triangles.concat(_compute_face_triangles(view, entity, transformation))
          elsif entity.is_a?(Sketchup::Group)
            triangles.concat(_compute_children_faces_tirangles(view, entity.entities, transformation ? transformation * entity.transformation : entity.transformation))
          elsif entity.is_a?(Sketchup::ComponentInstance) && entity.definition.behavior.cuts_opening?
            triangles.concat(_compute_children_faces_tirangles(view, entity.definition.entities, transformation ? transformation * entity.transformation : entity.transformation))
          end
        end
      }
      triangles
    end

    def _compute_face_triangles(view, face, transformation = nil)

      # Thank you @thomthom for this piece of code ;)

      if face.deleted?
        return false
      end

      mesh = face.mesh(0) # POLYGON_MESH_POINTS
      points = mesh.points

      _offset_toward_camera(view, points)
      _transform_points(points, transformation)

      triangles = []
      mesh.polygons.each { |polygon|
        polygon.each { |index|
          # Indicies start at 1 and can be negative to indicate edge smoothing.
          # Must take this into account when looking up the points in our array.
          triangles << points[index.abs - 1]
        }
      }

      triangles
    end

  end

end
