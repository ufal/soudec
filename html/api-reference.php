<?php $main_page=basename(__FILE__); require('header.php') ?>

<div class="dropdown pull-right" style='margin-left: 10px; margin-bottom: 10px'>
  <button class="btn btn-default dropdown-toggle" type="button" id="tocDropdown" data-toggle="dropdown"><span class="fa fa-bars"></span> Table of Contents <span class="caret"></span></button>
  <ul class="dropdown-menu dropdown-menu-right" aria-labelledby="tocDropdown">
    <li><a href="#api_reference">API Reference</a></li>
    <li><a href="#process"><span class="fa fa-caret-right"></span> <code>process</code></a></li>
    <li class="divider"></li>
    <li><a href="#using_curl">Accessing API using Curl</a></li>
  </ul>
</div>

<p>SouDeC REST API web service is available on
<code>http(s)://quest.ms.mff.cuni.cz/soudec/api/</code>.</p>

<?php require('licence.html') ?>

<h2 id="api_reference">API Reference</h2>

<p>The SouDeC REST API can be accessed <a href="run.php">directly</a> or via web
programming tools that support standard HTTP request methods and JSON for output
handling.</p>

<table class='table table-striped table-bordered'>
<tr>
    <th>Service Request</th>
    <th>Description</th>
    <th>HTTP Method</th>
</tr>
<tr>
    <td><a href="#detect">detect</a></td>
    <td><a href="http://ufal.mff.cuni.cz/soudec/users-manual#run_soudec">detect and classify sources</a></td>
    <td>GET/POST</td>
</tr>
</table>


<h3>Method <a id='detect'>detect</a></h3>

<p>Process the given data as described <a href="http://ufal.mff.cuni.cz/soudec/users-manual#run_soudec">in the User's Manual</a>.</p>

<table class='table table-striped table-bordered'>
<tr><th>Parameter</th><th>Mandatory</th><th>Data type</th><th>Description</th></tr>
<tr><td>text</td><td>yes</td><td>string</td><td>Input text in <b>UTF-8</b>.</td></tr>
<tr><td>input</td><td>no</td><td>string</td><td>Input format; possible values: <code>txt</code> (default), <code>presegmented</code>, see <a href="#input_format">input format</a> for details.</td></tr>
<tr><td>output</td><td>no</td><td>string</td><td>Output format; possible values: <code>txt</code> (default), <code>html</code>, <code>conllu</code>, see <a href="#output_format">output format</a> for details.</td></tr>
</table>

<p>
The response is in <a href="http://en.wikipedia.org/wiki/JSON">JSON</a> format of the
following structure:</p>

<pre class="prettyprint lang-json">
{
 "result": "processed_output"
}
</pre>

The <code>processed_output</code> is the output of SouDeC in the requested output format.


<h4>Browser Examples</h4>
<table style='width: 100%'>
 <tr><td style='vertical-align: middle'><pre style='margin-bottom: 0; white-space: pre-wrap' class="prettyprint lang-html">http://quest.ms.mff.cuni.cz/soudec/api/detect?input=txt&amp;output=txt&amp;text=SouDec tvrdí, že tohle je citace.</pre></td>
     <td style='vertical-align: middle; width: 6em'><button style='width: 100%' type="button" class="btn btn-success btn-xs" onclick="window.open('http://quest.ms.mff.cuni.cz/soudec/api/detect?input=txt&amp;output=txt&amp;text=SouDec tvrdí, že tohle je citace.')">try&nbsp;this</button></td></tr>
</table>

<hr />

<p>CHANGE FROM HERE!!!</p>

<hr />

<h2 id="using_curl">Accessing API using Curl</h2>

The described API can be comfortably used by <code>curl</code>. Several examples follow:

<h3>Passing Input on Command Line (if UTF-8 locale is being used)</h3>
<pre style="white-space: pre-wrap" class="prettyprint lang-sh">curl --data 'tokenizer=&tagger=&parser=&data=Děti pojedou k babičce. Už se těší.' http://lindat.mff.cuni.cz/services/udpipe/api/process</pre>

<h3>Using Files as Input (files must be in UTF-8 encoding)</h3>
<pre style="white-space: pre-wrap" class="prettyprint lang-sh">curl -F data=@input_file.txt -F tokenizer= -F tagger= -F parser= http://lindat.mff.cuni.cz/services/udpipe/api/process</pre>

<h3>Specifying Model Parameters</h3>
<pre style="white-space: pre-wrap" class="prettyprint lang-sh">curl -F data=@input_file.txt -F model=english -F tokenizer= -F tagger= -F parser= http://lindat.mff.cuni.cz/services/udpipe/api/process</pre>

<h3>Converting JSON Result to Plain Text</h3>
<pre style="white-space: pre-wrap" class="prettyprint lang-sh">curl -F data=@input_file.txt -F model=english -F tokenizer= -F tagger= -F parser= http://lindat.mff.cuni.cz/services/udpipe/api/process | PYTHONIOENCODING=utf-8 python -c "import sys,json; sys.stdout.write(json.load(sys.stdin)['result'])"</pre>

<?php require('footer.php') ?>
