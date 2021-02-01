+function ($) {
    'use strict';

    // CLASS DEFINITION
    // ======================

    var LadbTextinputCurrency = function (element, options) {
        LadbAbstractSimpleTextinput.call(this, element, options, '');
    };
    LadbTextinputCurrency.prototype = new LadbAbstractSimpleTextinput;

    LadbTextinputCurrency.DEFAULTS = {
        currency: '€'
    };

    LadbTextinputCurrency.prototype.init = function () {
        LadbAbstractSimpleTextinput.prototype.init.call(this);

        this.$element.before('<span class="input-group-addon">' + this.options.currency + '</span>');

    };


    // PLUGIN DEFINITION
    // =======================

    function Plugin(option, params) {
        return this.each(function () {
            var $this = $(this);
            var data = $this.data('ladb.textinputCurrency');
            var options = $.extend({}, LadbTextinputCurrency.DEFAULTS, $this.data(), typeof option == 'object' && option);

            if (!data) {
                $this.data('ladb.textinputCurrency', (data = new LadbTextinputCurrency(this, options)));
            }
            if (typeof option == 'string') {
                data[option].apply(data, Array.isArray(params) ? params : [ params ])
            } else {
                data.init();
            }
        })
    }

    var old = $.fn.ladbTextinputCurrency;

    $.fn.ladbTextinputCurrency = Plugin;
    $.fn.ladbTextinputCurrency.Constructor = LadbTextinputCurrency;


    // NO CONFLICT
    // =================

    $.fn.ladbTextinputCurrency.noConflict = function () {
        $.fn.ladbTextinputCurrency = old;
        return this;
    }

}(jQuery);