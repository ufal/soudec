<?php $main_page=basename(__FILE__); require('header.php') ?>

<?php require('about.html') ?>

<p>
Description of the available methods is available in the <a href="api-reference.php">API
Documentation</a>.
</p>

<script type="text/javascript"><!--
  var input_file_content = null;
  var output_file_content = null;
  var output_file_table = null;

  function doSubmit() {
    var model = jQuery('#model :selected').text();
    if (!model) return;

    var text;
    var input_tab = jQuery('#input_tabs>.tab-pane.active');
    if (input_tab.length > 0 && input_tab.attr('id') == 'input_file') {
      if (!input_file_content) { alert('Please load file first.'); return; }
      text = input_file_content;
    } else {
      text = jQuery('#input').val();
    }

    var options = {model: model, data: text};
    var input = jQuery('input[name=option_input]:checked').val();
    if (input && input == "tokenizer") {
      options.tokenizer = "";
      var opts = ["presegmented", "ranges", "normalized_spaces"];
      for (var i in opts)
        if (jQuery("#tokenizer_" + opts[i]).prop('checked')) options.tokenizer += (options.tokenizer ? ";" : "") + opts[i];
    } else {
      options.input = input ? input : "conllu";
    }
    if (jQuery('#tagger').prop('checked')) options.tagger = "";
    if (jQuery('#parser').prop('checked')) options.parser = "";

    var form_data = null;
    if (window.FormData) {
      form_data = new FormData();
      for (var key in options)
        form_data.append(key, options[key]);
    }

    output_file_content = null;
    output_file_table = null;
    output_file_tree = null;
    jQuery('#submit').html('<span class="fa fa-cog"></span> Waiting for Results <span class="fa fa-cog"></span>');
    jQuery('#submit').prop('disabled', true);
    jQuery.ajax('//lindat.mff.cuni.cz/services/udpipe/api/process',
           {data: form_data ? form_data : options, processData: form_data ? false : true,
            contentType: form_data ? false : 'application/x-www-form-urlencoded; charset=UTF-8',
            dataType: "json", type: "POST", success: function(json) {
      try {
        if ("result" in json) {
          output_file_content = json.result;
          jQuery('#output_text').html('<button id="save_file" class="btn btn-success form-control" type="submit" onclick="saveFile()"><span class="fa fa-download"></span> Save Output File</span></button><div class="well" id="output_text_content" style="white-space: pre-wrap; margin-top: 15px"></div>');
          jQuery('#output_text_content').text(output_file_content);

          var output_tab = jQuery('#output_tabs>.tab-pane.active');
          if (output_tab.length > 0 && output_tab.attr('id') == 'output_table') showTable(); else jQuery('#output_table').empty();
          if (output_tab.length > 0 && output_tab.attr('id') == 'output_tree') showTree(); else jQuery('#output_tree').empty();

          var acknowledgements = "";
          for (var a in json.acknowledgements)
            acknowledgements += "<a href='" + json.acknowledgements[a] + "'>" + json.acknowledgements[a] + "</a><br/>";
          jQuery('#acknowledgements_text').html(acknowledgements).show();
          jQuery('#acknowledgements_title').show();
          jQuery('#acknowledgements_text').show();
        }
      } catch(e) {
        jQuery('#submit').html('<span class="fa fa-arrow-down"></span> Process Input <span class="fa fa-arrow-down"></span>');
        jQuery('#submit').prop('disabled', false);
      }
    }, error: function(jqXHR, textStatus) {
      jQuery('#output_text').empty();
      jQuery('#output_tree').empty();
      alert("An error occurred" + ("responseText" in jqXHR ? ": " + jqXHR.responseText : "!"));
    }, complete: function() {
      jQuery('#submit').html('<span class="fa fa-arrow-down"></span> Process Input <span class="fa fa-arrow-down"></span>');
      jQuery('#submit').prop('disabled', false);
    }});
  }


--></script>

<div class="panel panel-info">
  <div class="panel-heading">Service</div>
  <div class="panel-body">

    <p>The service is freely available for testing. Respect the
    <a href="http://creativecommons.org/licenses/by-nc-sa/4.0/">CC BY-NC-SA</a>
    licence; <b>explicit written permission of the authors is
    required for any commercial exploitation of the system</b>. If you use the
    service, you agree that data obtained by us during such use can be used for further
    improvements of the systems at UFAL. All comments and reactions are welcome.</p>

    <div id="error" class="alert alert-danger" style="display: none"></div>

    <div class="form-horizontal">
      <div class="form-group row">
        <label class="col-sm-2 control-label">Input:</label>
        <div class="col-sm-10">
          <label title="Tokenize input using a tokenizer" class="radio-inline" id="option_input_plaintext"><input name="option_input" type="radio" value="plaintext" checked/>Plain text</label>
          <label title="Tokenize a pre-segmented input using a tokenizer" class="radio-inline" id="option_input_presegmented"><input name="option_input" type="radio" value="presegmented"/>Pre-segmented</label>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-sm-2 control-label">Output:</label>
        <div class="col-sm-10">
          <label title="TXT with sources and phrases marked with special characters" class="radio-inline" id="option_output_txt"><input name="option_output" type="radio" value="txt"/>TXT (<a href="http://ufal.mff.cuni.cz/soudec/1/users-manual#run_ner_output_formats">marked with special characters</a>)</label>
          <label title="HTML with colour-marked sources and phrases" class="radio-inline" id="option_output_html"><input name="option_output" type="radio" value="html" checked/>HTML (<a href="http://ufal.mff.cuni.cz/soudec/1/users-manual#run_ner_output_formats">colour-marked</a>)</label>
          <label title="CoNLL-U format with sources and phrases in MISC" class="radio-inline" id="option_output_conllu"><input name="option_output" type="radio" value="conllu"/>CoNLL-U (<a href="http://ufal.mff.cuni.cz/soudec/1/users-manual#run_ner_output_formats">CoNLL-U+NE+SD</a>)</label>
        </div>
      </div>
    </div>

    <ul class="nav nav-tabs nav-justified nav-tabs-green">
     <li class="active"><a href="#input_text" data-toggle="tab"><span class="fa fa-font"></span> Input Text</a></li>
    </ul>
    
    <div class="tab-content" id="input_tabs" style="border-right: 1px solid #ddd; border-left: 1px solid #ddd; border-bottom: 1px solid #ddd; border-bottom-right-radius: 5px; border-bottom-left-radius: 5px; padding: 15px">
     <div class="tab-pane active" id="input_text">
      <textarea id="input" class="form-control" rows="10" cols="80"></textarea>
     </div>
    </div>

    <button id="submit" class="btn btn-primary form-control" type="submit" style="margin-top: 15px; margin-bottom: 15px" onclick="doSubmit()"><span class="fa fa-arrow-down"></span> Process Input <span class="fa fa-arrow-down"></span></button>

    <ul class="nav nav-tabs nav-justified nav-tabs-green">
     <li class="active"><a href="#output_formatted" data-toggle="tab"><span class="fa fa-table"></span> Output</a></li>
    </ul>

    <div class="tab-content" id="output_tabs" style="border-right: 1px solid #ddd; border-left: 1px solid #ddd; border-bottom: 1px solid #ddd; border-bottom-right-radius: 5px; border-bottom-left-radius: 5px; padding: 15px">
     <div class="tab-pane active" id="output_formatted">
     </div>
    </div>

    <h3 id="acknowledgements_title" style="display: none; margin-top: 15px">Acknowledgements</h3>
    <p id="acknowledgements_text" style="display: none"> </p>
  </div>
</div>

<?php require('footer.php') ?>
