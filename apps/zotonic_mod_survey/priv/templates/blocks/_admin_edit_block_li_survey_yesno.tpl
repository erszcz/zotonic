{% extends "admin_edit_widget_i18n.tpl" %}

{% block widget_title %}
{_ Block _}
<div class="widget-header-tools"></div>
{% endblock %}

{% block widget_show_minimized %}false{% endblock %}
{% block widget_id %}edit-block-{{ name }}{% endblock %}
{% block widget_header %}{% endblock %}

{% block widget_content %}
    {% if id.is_editable %}
    <div class="form-group">
        <input class="form-control" type="text" id="block-{{name}}-prompt{{ lang_code_for_id }}" name="blocks[].prompt{{ lang_code_with_dollar }}" value="{{ blk.prompt[lang_code]  }}"
               placeholder="{_ Yes or no question _} ({{ lang_code }})" />
    </div>

    <div class="form-group view-expanded">
       <textarea class="form-control" id="block-{{name}}-explanation{{ lang_code_for_id }}" name="blocks[].explanation{{ lang_code_with_dollar }}" rows="2"
              placeholder="{_ Explanation _} ({{ lang_code }})" >{{ blk.explanation[lang_code]  }}</textarea>

    </div>

    <div class="form-group view-expanded">
       <div>
           <label class="radio-inline"><input type="radio" name="{{ name }}" class="nosubmit" />
               <input type="text" id="block-{{name}}-yes{{ lang_code_for_id }}" name="blocks[].yes{{ lang_code_with_dollar }}"
                     class="col-md-6 form-control" value="{{ blk.yes[lang_code]  }}"
                     placeholder="{_ Yes _}" />
           </label>
           <label class="radio-inline"><input type="radio" name="{{ name }}" class="nosubmit" />
               <input type="text" id="block-{{name}}-no{{ lang_code_for_id }}" name="blocks[].no{{ lang_code_with_dollar }}"
                     class="col-md-6 form-control" value="{{ blk.no[lang_code]  }}"
                     placeholder="{_ No _}" />
           </label>
       </div>
    </div>

    {% else %}
        <p>{{ blk.prompt[lang_code]  }}</p>
    {% endif %}
{% endblock %}

{% block widget_content_nolang %}
    <div class="form-group view-expanded question-options">
        <div class="checkbox">
          <label>
            <input type="checkbox" id="block-{{name}}-input_type" name="blocks[].input_type" value="submit" {% if blk.input_type == 'submit' %}checked="checked"{% endif %} />
            {_ Submit on clicking an option _}
          </label>
        </div>

        <div class="checkbox">
          <label>
            <input type="checkbox" id="block-{{name}}-is_required" name="blocks[].is_required" value="1" {% if blk.is_required or is_new %}checked="checked"{% endif %} />
            {_ Required, this question must be answered. _}
          </label>
        </div>

        <div class="checkbox">
          <label>
              <input type="checkbox" id="block-{{name}}-is_hide_result" name="blocks[].is_hide_result" value="1" {% if blk.is_hide_result %}checked="checked"{% endif %} />
              {_ Hide from results _}
          </label>
        </div>
    </div>
{% endblock %}
