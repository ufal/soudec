
<!-- Reading logs and preparation of a chart with access numbers for several past months -->

<?php
$monthsBack = 5; // Počet měsíců zpět, lze změnit
$logsDir = __DIR__ . '/log'; // Cesta k adresáři s logy
$logFilesPattern = 'api.log*'; // Vzor pro soubory (api.log, api.log.1, api.log.2.gz atd.)

// Získání aktuálního data (pro simulaci použijte zadané datum, v reálu date('Y-m-d H:i:s'))
//$now = new DateTime('2025-08-15');
$now = new DateTime();
$cutoffDate = (clone $now)->modify("-$monthsBack months")->setDate($now->format('Y'), $now->format('m') - $monthsBack + 1, 1); // První den nejstaršího měsíce

// Inicializace počtů přístupů
$accessCounts = [];
for ($i = 0; $i < $monthsBack; $i++) {
    $d = (clone $now)->modify("-$i months");
    $yearMonth = $d->format('Y-m');
    $accessCounts[$yearMonth] = 0;
}

// Načtení souborů pomocí glob
$logFiles = glob("$logsDir/$logFilesPattern");
if (empty($logFiles)) {
    die('Žádné logovací soubory nenalezeny.');
}

// Zpracování každého souboru
foreach ($logFiles as $file) {
    if (pathinfo($file, PATHINFO_EXTENSION) === 'gz') {
        // Komprimovaný soubor
        $handle = gzopen($file, 'r');
        if (!$handle) continue;
        while (($line = gzgets($handle)) !== false) {
            processLine($line, $cutoffDate, $accessCounts);
        }
        gzclose($handle);
    } else {
        // Nekomprimovaný soubor
        $handle = fopen($file, 'r');
        if (!$handle) continue;
        while (($line = fgets($handle)) !== false) {
            processLine($line, $cutoffDate, $accessCounts);
        }
        fclose($handle);
    }
}

// Funkce pro zpracování řádku
function processLine($line, $cutoffDate, &$accessCounts) {
    $line = trim($line);
    if (empty($line)) return;

    $parts = explode("\t", $line);
    if (count($parts) < 1) return;

    $dateStr = $parts[0];
    $logDate = DateTime::createFromFormat('D M d H:i:s Y', $dateStr);
    if (!$logDate) return; // Neplatné datum

    if ($logDate >= $cutoffDate) {
        $yearMonth = $logDate->format('Y-m');
        if (isset($accessCounts[$yearMonth])) {
            $accessCounts[$yearMonth]++;
        }
    }
}

// Příprava dat pro graf
$labels = array_keys($accessCounts);
sort($labels); // Vzestupně (nejstarší napřed)
$data = [];
foreach ($labels as $label) {
    $data[] = $accessCounts[$label];
}
$labelsJson = json_encode($labels);
$dataJson = json_encode($data);
?>


<script type="text/javascript"><!--
  var input_file_content = null;
  var output_file_content = null;
  var output_file_stats = null;
  var output_format = null;


  document.addEventListener("DOMContentLoaded", function() {
    getInfo(); // get the server version
    displayShortSelectedOptions(); // display default settings at the info bar
    createAccessCountChart();
  
    const textarea = document.getElementById('input');
    let originalValue = textarea.value;

    textarea.addEventListener('focus', function() {
        if (this.value === originalValue) {
            this.value = '';
            this.style.color = '#333333'; // Změní barvu na tmavou při psaní
        }
    });

    // Nastavení barvy pro předvyplněný text při načtení
    textarea.style.color = '#bbbbbb';
  });


  function createAccessCountChart () {
        const ctx = document.getElementById('accessChart').getContext('2d');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: <?php echo $labelsJson; ?>,
                datasets: [{
                    label: 'Počet přístupů',
                    data: <?php echo $dataJson; ?>,
                    backgroundColor: '#36A2EB',
                    borderColor: '#1E87D6',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: false, /* Zakázáno pro pevnou velikost */
                animation: false, /* Zakázání animací */
                plugins: {
                    legend: {
                        position: 'top',
                        labels: {
                            color: '#333',
                            font: { size: 12 }
                        }
                    },
                    title: {
                        display: true,
                        text: 'Počet přístupů za poslední měsíce',
                        color: '#333',
                        font: { size: 14 }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Počet přístupů',
                            color: '#333',
                            font: { size: 12 }
                        },
                        ticks: { color: '#333', font: { size: 10 } }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Měsíc',
                            color: '#333',
                            font: { size: 12 }
                        },
                        ticks: { color: '#333', font: { size: 10 } }
                    }
                }
            }
        });

  }





  function doSubmit() {
    //var model = jQuery('#model :selected').text();
    //if (!model) return;

    var input_text = jQuery('#input').val();
    // console.log("doSubmit: Input text: ", input_text);
    var input_format = jQuery('input[name=option_input]:checked').val();
    // console.log("doSubmit: Input format: ", input_format);
    output_format = jQuery('input[name=option_output]:checked').val();
    // console.log("doSubmit: Output format: ", output_format);

    <?php
      if ($currentLang == 'cs') {
    ?>
      var ui_lang = 'cs'; 
    <?php
      } else {
    ?>
      var ui_lang = 'en'; 
    <?php
      }
    ?>

    var options = {text: input_text, input: input_format, output: output_format, uilang: ui_lang, stats: 'html'};
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
    jQuery('#submit').html('<span class="spinner-border spinner-border-sm" style="width: 1.2rem; height: 1.2rem;" role="status" aria-hidden="true"></span>&nbsp;<?php echo $lang[$currentLang]['run_process_input_processing']; ?>&nbsp;<span class="spinner-border spinner-border-sm" style="width: 1.2rem; height: 1.2rem; animation-direction: reverse;" role="status" aria-hidden="true"></span>');
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
	  if ("stats_html" in json) {
              output_file_stats = json.stats_html;
              jQuery('#output_stats').html(output_file_stats);
	  }

      } catch(e) {
        jQuery('#submit').html('<span class="fa fa-arrow-down"></span> Process Input <span class="fa fa-arrow-down"></span>');
        jQuery('#submit').prop('disabled', false);
      }
    }, error: function(jqXHR, textStatus) {
      alert("An error occurred" + ("responseText" in jqXHR ? ": " + jqXHR.responseText : "!"));
    }, complete: function() {
        jQuery('#submit').html('<span class="fa fa-arrow-down"></span> <?php echo $lang[$currentLang]['run_process_input']; ?> <span class="fa fa-arrow-down"></span>');
        jQuery('#submit').prop('disabled', false);
    }});
  }


  function getInfo() { // call the server and get the DReUD version and a list of supported features

    <?php
      if ($currentLang == 'cs') {
    ?>
    var options = {info: null, uilang: 'cs'};
    <?php
      } else {
    ?>
    var options = {info: null, uilang: 'en'};
    <?php
      }
    ?>
    //console.log("getInfo: options: ", options);

    var form_data = null;
    if (window.FormData) {
      form_data = new FormData();
      for (var key in options)
        form_data.append(key, options[key]);
    }

    var version = '<?php echo $lang[$currentLang]['run_server_info_version_unknown']; ?> (<font color="red"><?php echo $lang[$currentLang]['run_server_info_status_error']; ?>!</font>)';
    //console.log("Calling api/info");
    jQuery.ajax('//quest.ms.mff.cuni.cz/soudec/api/info',
           {data: form_data ? form_data : options, processData: form_data ? false : true,
            contentType: form_data ? false : 'application/x-www-form-urlencoded; charset=UTF-8',
            dataType: "json", type: "POST", success: function(json) {
      try {
        if ("version" in json) {
          version = json.version;
          version += ', <span style="font-style: normal"><?php echo $lang[$currentLang]['run_server_info_status']; ?>:</span> <font color="green">online</font>';
          //console.log("json.version: ", version);
        }

      } catch(e) {
        // no need to do anything
      }
    }, error: function(jqXHR, textStatus) {
      console.log("An error occurred " + ("responseText" in jqXHR ? ": " + jqXHR.responseText : "!"));
    }, complete: function() {
      //console.log("Complete.");
      var info = "<h4><?php echo $lang[$currentLang]['run_server_info_label']; ?></h4>\n<ul><li><?php echo $lang[$currentLang]['run_server_info_version']; ?>: <i>" + version + "</i>\n</ul>\n";
      //console.log("Info: ", info);
      document.getElementById('server_info').innerHTML = info;
      document.getElementById('server_info').classList.remove('d-none');

      var short_info = "&nbsp; <?php echo $lang[$currentLang]['run_server_info_version']; ?>: <i>" + version + "</i>";
      //console.log("Short info: ", short_info);
      document.getElementById('server_short_info').innerHTML = short_info;
      document.getElementById('server_short_info').classList.remove('d-none');
      
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

  function displayShortSelectedOptions() {
    // Získání vybraného formátu vstupu
    const inputOptions = document.getElementsByName('option_input');
    let selectedInput = '';
    let selectedInputLabel = '';
    for (const option of inputOptions) {
        if (option.checked) {
            selectedInput = option.id;
            selectedInputLabel = document.querySelector(`label[for="${selectedInput}"]`).textContent.trim();
            break;
        }
    }

    // Získání vybraného výstupního formátu 
    const outputOptions = document.getElementsByName('option_output');
    let selectedOutput = '';
    let selectedOutputLabel = '';
    for (const option of outputOptions) {
        if (option.checked) {
            selectedOutput = option.id;
            selectedOutputLabel = document.querySelector(`label[for="${selectedOutput}"]`).textContent.trim();
            break;
        }
    }

    // Získání názvů popisků
    const inputLabel = "<span class=\"fw-bold me-2\"><?php echo $lang[$currentLang]['run_options_input_label']; ?>:</span>";
    const outputLabel = "<span class=\"fw-bold ms-3 me-2\"><?php echo $lang[$currentLang]['run_options_output_label']; ?>:</span>";

    // Sestavení výsledného řetězce
    document.getElementById('options_short_info').innerHTML = `${inputLabel} ${selectedInputLabel}, ${outputLabel} ${selectedOutputLabel}`;
    // Collapse the options panel after an option has been changed:
    const aboutContent = document.getElementById('aboutContent');
    const collapse = new bootstrap.Collapse(aboutContent, { toggle: false });
    collapse.hide();
  }


--></script>


<!-- ================= OPTIONS ================ -->

<!-- ================= Options card ================ -->
<div class="card">
  <div class="card-header p-0" role="tab" id="aboutHeading">
    <button class="btn btn-link collapsed py-2 px-3 w-100 text-start d-block text-decoration-none" type="button" data-bs-toggle="collapse" data-bs-target="#aboutContent" aria-expanded="false" aria-controls="aboutContent">
      <i class="fa-solid fa-caret-down"></i> <span id="options_short_info"></span>
    </button>
  </div>
  <!-- ================= Options panel ================ -->
  <div id="aboutContent" class="collapse m-1" role="tabpanel" aria-labelledby="aboutHeading">

    <!-- ================= input format ================ -->
    <div class="row gx-2 gy-0 mt-lg-3 mb-lg-3">
      <div class="col-12 col-md-2 text-end">
        <label class="form-label fw-bold me-5"><?php echo $lang[$currentLang]['run_options_input_label']; ?>:</label>
      </div>
      <div class="col-12 col-md-10">
        <div class="form-check form-check-inline">
          <input class="form-check-input" type="radio" name="option_input" id="option_input_plaintext" value="txt" checked onchange="displayShortSelectedOptions();">
          <label class="form-check-label" for="option_input_plaintext" title="<?php echo $lang[$currentLang]['run_options_input_plain_popup']; ?>">
            <?php echo $lang[$currentLang]['run_options_input_plain']; ?>
          </label>
        </div>
        <div class="form-check form-check-inline">
          <input class="form-check-input" type="radio" name="option_input" id="option_input_presegmented" value="presegmented" onchange="displayShortSelectedOptions();">
          <label class="form-check-label" for="option_input_presegmented" title="<?php echo $lang[$currentLang]['run_options_input_presegmented_popup']; ?>">
            <?php echo $lang[$currentLang]['run_options_input_presegmented']; ?>
          </label>
        </div>

      </div>

      <!-- ================= output format ================ -->
      <div class="col-12 col-md-2 text-end">
        <label class="form-label fw-bold me-5"><?php echo $lang[$currentLang]['run_options_output_label']; ?>:</label>
      </div>
      <div class="col-12 col-md-10">
        <div class="form-check form-check-inline">
          <input class="form-check-input" type="radio" name="option_output" id="option_output_txt" value="txt" onchange="displayShortSelectedOptions();">
          <label class="form-check-label" for="option_output_txt" title="<?php echo $lang[$currentLang]['run_options_output_txt_popup']; ?>">
            <?php echo $lang[$currentLang]['run_options_output_txt']; ?>
          </label>
	</div>

        <div class="form-check form-check-inline">
          <input class="form-check-input" type="radio" name="option_output" id="option_output_html" value="html" checked onchange="displayShortSelectedOptions();">
          <label class="form-check-label" for="option_output_html" title="<?php echo $lang[$currentLang]['run_options_output_html_popup']; ?>">
            <?php echo $lang[$currentLang]['run_options_output_html']; ?>
          </label>
	</div>

        <div class="form-check form-check-inline">
          <input class="form-check-input" type="radio" name="option_output" id="option_output_conllu" value="conllu" onchange="displayShortSelectedOptions();">
          <label class="form-check-label" for="option_output_conllu" title="<?php echo $lang[$currentLang]['run_options_output_conllu_popup']; ?>">
            <?php echo $lang[$currentLang]['run_options_output_conllu']; ?>
          </label>
        </div>
      </div>
    </div>
  </div>

  <!-- ================= INPUT FIELDS ================ -->

  <!-- ================ záložky input panelů =============== -->
  <ul class="nav nav-tabs nav-fill nav-tabs-green">
    <li class="nav-item" id="input_text_header">
      <a class="nav-link active d-flex align-items-center" href="#input_text" data-bs-toggle="tab">
        <span class="fa fa-font"></span>&nbsp;<?php echo $lang[$currentLang]['run_input_text']; ?>
        <div class="ms-auto d-flex gap-2">
          <button class="btn btn-sm btn-primary btn-soudec-colors btn-soudec-small" onclick="var t=document.getElementById('input'); t.value=''; t.focus();" title="<?php echo $lang[$currentLang]['run_input_text_button_delete_tooltip']; ?>">
            <span class="fas fa-trash"></span> <?php echo $lang[$currentLang]['run_input_text_button_delete']; ?>
          </button>
        </div>
      </a>
    </li>
  </ul>

  <!-- ================ input panel =============== -->
  <div class="tab-content" id="input_tabs" style="border: 1px solid #ddd; border-radius: 0 0 .25rem .25rem; padding: 15px;">
    <div class="tab-pane show active" id="input_text">
      <textarea id="input" class="form-control" rows="10" cols="80"><?php echo $lang['cs']['run_input_text_default_text']; ?></textarea>
    </div>
  </div>

  <!-- ================= THE MAIN PROCESS BUTTON ================ -->

  <button id="submit" class="btn btn-primary btn-soudec-colors form-control mt-3" type="submit" onclick="doSubmit()">
    <span class="fa fa-arrow-down"></span> <?php echo $lang[$currentLang]['run_process_input']; ?> <span class="fa fa-arrow-down"></span>
  </button>

  <!-- ================= OUTPUT FIELDS ================ -->
    
  <ul class="nav nav-tabs nav-tabs-green nav-tabs-custom nav-fill">

    <!-- output text tab -->
    <li class="nav-item" id="output_text_header">
      <a class="nav-link active d-flex align-items-center" href="#output_formatted" data-bs-toggle="tab">
        <span class="fa fa-font me-2"></span>
        <span><?php echo $lang[$currentLang]['run_output_text']; ?></span>
        <div class="ms-auto d-flex gap-2">
          <button class="btn btn-primary btn-sm btn-soudec-colors btn-soudec-small" onclick="saveOutput(); event.stopPropagation();">
            <span class="fa fa-download"></span>
          </button>
        </div>
      </a>
    </li>

    <!-- output stats tab -->
    <li class="nav-item" id="output_stats_header">
      <a class="nav-link d-flex align-items-center" href="#output_stats" data-bs-toggle="tab">
        <span class="fa fa-font me-2"></span>
        <span><?php echo $lang[$currentLang]['run_output_statistics']; ?></span>
        <div class="ms-auto d-flex gap-2">
          <button class="btn btn-primary btn-sm btn-soudec-colors btn-soudec-small" onclick="saveStats(); event.stopPropagation();">
            <span class="fa fa-download"></span>
          </button>
        </div>
      </a>
    </li>

  </ul>

  <!-- output panels -->
  <div class="tab-content" id="output_tabs" style="border-right: 1px solid #ddd; border-left: 1px solid #ddd; border-bottom: 1px solid #ddd; border-bottom-right-radius: 5px; border-bottom-left-radius: 5px; padding: 15px;">
    <div class="tab-pane active" id="output_formatted" style="min-height: 300px; max-height: 85vh; overflow-y: auto;"></div>
    <div class="tab-pane" id="output_stats" style="min-height: 300px; max-height: 85vh; overflow-y: auto;"></div>
  </div>

</div>

