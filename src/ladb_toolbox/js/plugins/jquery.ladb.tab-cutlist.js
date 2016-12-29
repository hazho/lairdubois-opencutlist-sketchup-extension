+function ($) {
    'use strict';

    var OPTION_KEY_PART_NUMBER_WITH_LETTERS = 'cutlist_part_number_with_letters';
    var OPTION_KEY_PART_NUMBER_SEQUENCE_BY_GROUP = 'cutlist_part_number_sequence_by_group';

    // CLASS DEFINITION
    // ======================

    var LadbTabCutlist = function (element, settings, toolbox) {
        this.settings = settings;
        this.$element = $(element);
        this.toolbox = toolbox;

        this.groups = [];
        this.materialUsages = [];
        this.editedPart = null;

        this.options = {
            part_number_with_letters: this.toolbox.getSettingsValue(OPTION_KEY_PART_NUMBER_WITH_LETTERS, true),
            part_number_sequence_by_group: this.toolbox.getSettingsValue(OPTION_KEY_PART_NUMBER_SEQUENCE_BY_GROUP, false)
        };

        this.$fileTabs = $('.ladb-file-tabs', this.$element);
        this.$btnGenerate = $('#ladb_btn_generate', this.$element);
        this.$btnPrint = $('#ladb_btn_print', this.$element);
        this.$panelHelp = $('.ladb-panel-help', this.$element);

        this.$page = $('.ladb-page', this.$element);

        this.$modalOptions = $('#ladb_cutlist_modal_options', this.$element);
        this.$inputPartNumberWithLetters = $('#ladb_input_part_number_with_letters', this.$modalOptions);
        this.$inputPartNumberSequenceByGroup = $('#ladb_input_part_number_sequence_by_group', this.$modalOptions);

        this.$modalEditPart = $('#ladb_cutlist_modal_part', this.$element);
        this.$btnPartUpdate = $('#ladb_cutlist_part_update', this.$modalEditPart);
        this.$selectMaterialName = $('#ladb_cutlist_part_select_material_name', this.$modalEditPart);
        this.$inputPartName = $('#ladb_cutlist_part_input_name', this.$modalEditPart);
    };

    LadbTabCutlist.DEFAULTS = {};

    LadbTabCutlist.prototype.generateCutlist = function () {
        var that = this;

        this.groups = [];
        this.$page.empty();
        this.$btnGenerate.prop('disabled', true);

        rubyCallCommand('cutlist_generate', this.options, function(data) {

            var errors = data.errors;
            var warnings = data.warnings;
            var filename = data.filename;
            var pageLabel = data.page_label;
            var materialUsages = data.material_usages;
            var groups = data.groups;

            // Keep usefull data
            that.groups = groups;
            that.materialUsages = materialUsages;

            // Update filename
            that.$fileTabs.empty();
            that.$fileTabs.append(Twig.twig({ ref: "tabs/cutlist/_file-tab.twig" }).render({
                filename: filename,
                pageLabel: pageLabel
            }));

            // Hide help panel
            if (groups.length > 0) {
                that.$panelHelp.hide();
            }

            // Update print button state
            that.$btnPrint.prop('disabled', groups.length == 0);

            // Update page
            that.$page.empty();
            that.$page.append(Twig.twig({ ref: "tabs/cutlist/_list.twig" }).render({
                errors: errors,
                warnings: warnings,
                groups: groups
            }));

            // Init tooltips
            $('[data-toggle="tooltip"]').tooltip();

            // Bind buttons
            $('.ladb-btn-toggle-no-print', that.$page).on('click', function() {
                var $i = $('i', $(this));
                var groupId = $(this).data('group-id');
                var $group = $('#' + groupId);
                $group.toggleClass('no-print');
                if ($group.hasClass('no-print')) {
                    $i.removeClass('ladb-toolbox-icon-eye-close');
                    $i.addClass('ladb-toolbox-icon-eye-open');
                } else {
                    $i.addClass('ladb-toolbox-icon-eye-close');
                    $i.removeClass('ladb-toolbox-icon-eye-open');
                }
                $(this).blur();
            });
            $('a.ladb-scrollto', that.$page).on('click', function() {
                var target = $(this).attr('href');
                $('html, body').animate({ scrollTop: $(target).offset().top - 20 }, 500).promise().then(function() {
                    $(target).effect("highlight", {}, 1500);
                });
                $(this).blur();
                return false;
            });
            $('a.ladb-btn-edit', that.$page).on('click', function() {
                var partGuid = $(this).data('part-id');
                that.editPart(partGuid);
                $(this).blur();
                return false;
            });

            // Restore button state
            that.$btnGenerate.prop('disabled', false);

        });

    };

    LadbTabCutlist.prototype.findPartById = function (id) {
        for (var i = 0 ; i < this.groups.length; i++) {
            var group = this.groups[i];
            for (var j = 0; j < group.parts.length; j++) {
                var part = group.parts[j];
                if (part.id == id) {
                    return part;
                }
            }
        }
        return null;
    };

    LadbTabCutlist.prototype.editPart = function (id) {
        var that = this;

        var part = this.findPartById(id);
        if (part) {

            rubyCallCommand('cutlist_part_get_thumbnail', part, function(data) {

                var thumbnailFile = data['thumbnail_file'];

                var $imgThumbnail = $('.ladb-part-thumbnail', that.$modalEditPart);
                $imgThumbnail.attr('src', thumbnailFile);

                // Keep the edited part
                that.editedPart = part;

                // Populate material select
                that.$selectMaterialName.empty();
                that.$selectMaterialName.append(Twig.twig({ ref: "tabs/cutlist/_material_usages.twig" }).render({
                    materialUsages: that.materialUsages
                }));

                // Form fields
                that.$inputPartName.val(part.name);
                that.$selectMaterialName.val(part.material_name);

                // Refresh select
                that.$selectMaterialName.selectpicker('refresh');

                that.$modalEditPart.modal('show');

            });

        }
    };

    LadbTabCutlist.prototype.bind = function () {
        var that = this;

        // Bind buttons
        this.$btnGenerate.on('click', function () {
            that.generateCutlist();
            this.blur();
        });
        this.$btnPrint.on('click', function () {
            window.print();
            this.blur();
        });
        this.$btnPartUpdate.on('click', function () {

            that.editedPart.name = that.$inputPartName.val();
            that.editedPart.material_name = that.$selectMaterialName.val();

            rubyCallCommand('cutlist_part_update', that.editedPart, function() {

                // Reset edited part
                that.editedPart = null;

                // Hide modal
                that.$modalEditPart.modal('hide');

                // Refresh the list
                that.generateCutlist();

            });

        });

        // Bind inputs
        this.$inputPartNumberWithLetters.on('change', function () {
            that.options.part_number_with_letters = that.$inputPartNumberWithLetters.is(':checked');
            that.toolbox.setSettingsValue(OPTION_KEY_PART_NUMBER_WITH_LETTERS, that.options.part_number_with_letters);
        });
        this.$inputPartNumberSequenceByGroup.on('change', function () {
            that.options.part_number_sequence_by_group = that.$inputPartNumberSequenceByGroup.is(':checked');
            that.toolbox.setSettingsValue(OPTION_KEY_PART_NUMBER_SEQUENCE_BY_GROUP, that.options.part_number_sequence_by_group);
        });

    };

    LadbTabCutlist.prototype.init = function () {
        this.bind();

        // Init inputs values
        this.$inputPartNumberWithLetters.prop('checked', this.options.part_number_with_letters);
        this.$inputPartNumberSequenceByGroup.prop('checked', this.options.part_number_sequence_by_group);

        // Init selects
        this.$selectMaterialName.selectpicker({
            size: 10,
            iconBase: 'ladb-toolbox-icon',
            tickIcon: 'ladb-toolbox-icon-tick',
            showTick: true
        });

    };


    // PLUGIN DEFINITION
    // =======================

    function Plugin(setting, params) {
        return this.each(function () {
            var $this = $(this);
            var data = $this.data('ladb.tabCutlist');
            var settings = $.extend({}, LadbTabCutlist.DEFAULTS, $this.data(), typeof setting == 'object' && setting);

            if (!data) {
                if (settings.toolbox == undefined) {
                    throw 'toolbox option is mandatory.';
                }
                $this.data('ladb.tabCutlist', (data = new LadbTabCutlist(this, settings, settings.toolbox)));
            }
            if (typeof setting == 'string') {
                data[setting](params);
            } else {
                data.init();
            }
        })
    }

    var old = $.fn.ladbTabCutlist;

    $.fn.ladbTabCutlist = Plugin;
    $.fn.ladbTabCutlist.Constructor = LadbTabCutlist;


    // NO CONFLICT
    // =================

    $.fn.ladbTabCutlist.noConflict = function () {
        $.fn.ladbTabCutlist = old;
        return this;
    }

}(jQuery);