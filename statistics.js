/**
 * Statistics plotter for ATCA and Parkes.
 * Jamie Stevens 2019
 */

// Load our data.
var atcaFile = "atca_statistics.json";
var parkesFile = "parkes_statistics.json";

const loadFile = function(fname, callback) {
  var xhr = new XMLHttpRequest();
  xhr.open('GET', fname, true);
  xhr.reponseType = "json";
  xhr.onload = function() {
    var status = xhr.status;
    if (status === 200) {
      callback(null, xhr.response);
    } else {
      callback(status, xhr.response);
    }
  };
  xhr.send();
};

const fileLoaded = function(data) {
  console.log(data);
};

var atcaStats = loadFile(atcaFile, fileLoaded);
