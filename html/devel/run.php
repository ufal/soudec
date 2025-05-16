
<script type="text/javascript"><!--
  var input_file_content = null;
  var output_file_content = null;
  var output_file_stats = null;
  var output_format = null;

  function doSubmit() {
    //var model = jQuery('#model :selected').text();
    //if (!model) return;

    var input_text = jQuery('#input').val();
    // console.log("doSubmit: Input text: ", input_text);
    var input_format = jQuery('input[name=option_input]:checked').val();
    // console.log("doSubmit: Input format: ", input_format);
    output_format = jQuery('input[name=option_output]:checked').val();
    // console.log("doSubmit: Output format: ", output_format);
    var options = {text: input_text, input: input_format, output: output_format};
    // console.log("doSubmit: options: ", options);

    var form_data = null;
    if (window.FormData) {
      form_data = new FormData();
      for (var key in options)
        form_data.append(key, options[key]);
    }

    output_file_content = null;
    jQuery('#output_formatted').empty();
    jQuery('#output_stats').empty();
    jQuery('#submit').html('<span class="fa fa-cog"></span> Waiting for Results <span class="fa fa-cog"></span>');
    jQuery('#submit').prop('disabled', true);
    jQuery.ajax('//quest.ms.mff.cuni.cz/soudec/api/detect',
           {data: form_data ? form_data : options, processData: form_data ? false : true,
            contentType: form_data ? false : 'application/x-www-form-urlencoded; charset=UTF-8',
            dataType: "json", type: "POST", success: function(json) {
      try {
	  if ("result" in json) {
              output_file_content = json.result;
              // Přidání <br> ke každému novému řádku v proměnné output_file_content
              var formatted_content = output_format == "html" ? output_file_content : output_file_content.replace(/\n/g, "\n<br>");
              jQuery('#output_formatted').html(formatted_content);
	  }
	  if ("stats" in json) {
              output_file_stats = json.stats;
              jQuery('#output_stats').html(output_file_stats);
	  }

      } catch(e) {
        jQuery('#submit').html('<span class="fa fa-arrow-down"></span> Process Input <span class="fa fa-arrow-down"></span>');
        jQuery('#submit').prop('disabled', false);
      }
    }, error: function(jqXHR, textStatus) {
      alert("An error occurred" + ("responseText" in jqXHR ? ": " + jqXHR.responseText : "!"));
    }, complete: function() {
      jQuery('#submit').html('<span class="fa fa-arrow-down"></span> Process Input <span class="fa fa-arrow-down"></span>');
      jQuery('#submit').prop('disabled', false);
    }});
  }

  function saveAs(blob, file_name) {
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = file_name;
    a.style.display = 'none';
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    document.body.removeChild(a);
  }

  function saveOutput() {
    if (!output_file_content || !output_format) return;
    var content_blob = new Blob([output_file_content], {type: output_format == "html" ? "text/html" : "text/plain"});
    saveAs(content_blob, "citations." + output_format);
  }

  function saveStats() {
    if (!output_file_stats) return;
    var stats_blob = new Blob([output_file_stats], {type: "text/html"});
    saveAs(stats_blob, "statistics.html");
  }


--></script>

<div class="panel panel-default">
  <div class="panel-heading" role="tab" id="aboutHeading">
    <div class="collapsed" role="button" data-toggle="collapse" href="#aboutContent" aria-expanded="false" aria-controls="aboutContent">
      <span class="glyphicon glyphicon-triangle-bottom" aria-hidden="true"></span> SouDeC is an on-line tool and REST API service for detecting and classifying citation sources in Czech texts.
    </div>
  </div>
</div>

  <!-- ================= OPTIONS ================ -->

    <div class="form-horizontal">
      <div class="form-group row" style="margin-top: 10px; margin-bottom: 0px">
        <label class="col-sm-2 control-label">Input:</label>
        <div class="col-sm-10">
          <label title="Tokenize input using a tokenizer" class="radio-inline" id="option_input_plaintext"><input name="option_input" type="radio" value="txt" checked/>Plain text</label>
          <label title="Tokenize a pre-segmented input using a tokenizer" class="radio-inline" id="option_input_presegmented"><input name="option_input" type="radio" value="presegmented"/>Pre-segmented (<a href="http://ufal.mff.cuni.cz/soudec/users-manual#run_soudec_input" target="_blank">sentence per line</a>)</label>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-sm-2 control-label">Output:</label>
        <div class="col-sm-10">
          <label title="TXT with sources and phrases marked with special characters" class="radio-inline" id="option_output_txt"><input name="option_output" type="radio" value="txt"/>TXT (<a href="http://ufal.mff.cuni.cz/soudec/users-manual#run_soudec_output" target="_blank">marked with special characters</a>)</label>
          <label title="HTML with colour-marked sources and phrases" class="radio-inline" id="option_output_html"><input name="option_output" type="radio" value="html" checked/>HTML (<a href="http://ufal.mff.cuni.cz/soudec/users-manual#run_soudec_output" target="_blank">colour-marked</a>)</label>
          <label title="CoNLL-U format with sources and phrases in MISC" class="radio-inline" id="option_output_conllu"><input name="option_output" type="radio" value="conllu"/>CoNLL-U (<a href="http://ufal.mff.cuni.cz/soudec/users-manual#run_soudec_output" target="_blank">CoNLL-U+NE+SD</a>)</label>
        </div>
      </div>
    </div>

    <ul class="nav nav-tabs nav-justified nav-tabs-green">
     <li class="active" style="position:relative"><a href="#input_text" data-toggle="tab"><span class="fa fa-font"></span> Input Text</a>
          <button type="button" class="btn btn-primary btn-xs" style="position:absolute; top: 11px; right: 10px; padding: 0 2em" onclick="var t=document.getElementById('input'); t.value=''; t.focus();">Delete input text</button>
     </li>
    </ul>

    
    <div class="tab-content" id="input_tabs" style="border-right: 1px solid #ddd; border-left: 1px solid #ddd; border-bottom: 1px solid #ddd; border-bottom-right-radius: 5px; border-bottom-left-radius: 5px; padding: 15px">
     <div class="tab-pane active" id="input_text">
      <textarea id="input" class="form-control" rows="10" cols="80"></textarea>
     </div>
    </div>

    <button id="submit" class="btn btn-primary form-control" type="submit" style="margin-top: 15px; margin-bottom: 15px" onclick="doSubmit()"><span class="fa fa-arrow-down"></span> Process Input <span class="fa fa-arrow-down"></span></button>

    <ul class="nav nav-tabs nav-justified nav-tabs-green">
     <li class="active" style="position:relative"><a href="#output_formatted" data-toggle="tab"><span class="fa fa-font"></span> Output</a>
          <button type="button" class="btn btn-primary btn-xs" style="position:absolute; top: 11px; right: 10px; padding: 0 2em" onclick="saveOutput();"><span class="fa fa-download"></span> Save</button>
     </li>
     <li style="position:relative"><a href="#output_stats" data-toggle="tab"><span class="fa fa-table"></span> Statistics</a>
          <button type="button" class="btn btn-primary btn-xs" style="position:absolute; top: 11px; right: 10px; padding: 0 2em" onclick="saveStats();"><span class="fa fa-download"></span> Save</button>
     </li>
    </ul>

    <div class="tab-content" id="output_tabs" style="border-right: 1px solid #ddd; border-left: 1px solid #ddd; border-bottom: 1px solid #ddd; border-bottom-right-radius: 5px; border-bottom-left-radius: 5px; padding: 15px">
     <div class="tab-pane active" id="output_formatted">
     </div>
     <div class="tab-pane" id="output_stats">
     </div>
    </div>

  </div>

