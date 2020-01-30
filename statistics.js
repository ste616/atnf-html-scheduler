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
      callback(null, JSON.parse(xhr.response));
    } else {
      callback(status, xhr.response);
    }
  };
  xhr.send();
};

// Plot some diversity statistics.
const plotDiversity = function(data) {
  console.log(data);

  // The representation plot.
  var repPlotDiv = document.getElementById(
    data.observatory + "_diversity_representation");
  var sucPlotDiv = document.getElementById(
    data.observatory + "_diversity_success");
  // Format the data.
  var labels = [];
  var maleData = [];
  var femaleData = [];
  var malePhdData = [];
  var femalePhdData = [];
  var maleSuccessfulData = [];
  var femaleSuccessfulData = [];
  var malePhdSuccessfulData = [];
  var femalePhdSuccessfulData = [];
  var unspecifiedData = [];
  var unspecifiedPhdData = [];
  var unspecifiedSuccessfulData = [];
  var unspecifiedPhdSuccessfulData = [];
  for (var i = 0; i < data.semesterNames.length; i++) {
    var semName = data.semesterNames[i];
    if (data.projectDetails.hasOwnProperty(semName) &&
	(data.projectDetails[semName].successful.male_pi > 0)) {
      labels.push(semName.toUpperCase());
      maleData.push(data.projectDetails[semName].proposed.male_pi);
      femaleData.push(data.projectDetails[semName].proposed.female_pi);
      unspecifiedData.push(data.projectDetails[semName].proposed.notspecified_pi);
      malePhdData.push(data.projectDetails[semName].proposed.phd_male_pi);
      femalePhdData.push(data.projectDetails[semName].proposed.phd_female_pi);
      unspecifiedPhdData.push(data.projectDetails[semName].proposed.phd_notspecified_pi);
      var msr = data.projectDetails[semName].successful.male_pi /
	  data.projectDetails[semName].proposed.male_pi;
      var fsr = data.projectDetails[semName].successful.female_pi /
	  data.projectDetails[semName].proposed.female_pi;
      var usr = data.projectDetails[semName].successful.notspecified_pi /
	  data.projectDetails[semName].proposed.notspecified_pi;
      maleSuccessfulData.push(msr * 100);
      femaleSuccessfulData.push(fsr * 100);
      unspecifiedSuccessfulData.push(usr * 100);
      var mpsr = data.projectDetails[semName].successful.phd_male_pi /
	  data.projectDetails[semName].proposed.phd_male_pi;
      var fpsr = data.projectDetails[semName].successful.phd_female_pi /
	  data.projectDetails[semName].proposed.phd_female_pi;
      var upsr = data.projectDetails[semName].successful.phd_notspecified_pi /
	  data.projectDetails[semName].proposed.phd_notspecified_pi;
      malePhdSuccessfulData.push(mpsr * 100);
      femalePhdSuccessfulData.push(fpsr * 100);
      unspecifiedPhdSuccessfulData.push(upsr * 100);
    }
  }
  var maleColor = "#ffd700";
  var malePhdColor = "#32cd32";
  var femaleColor = "#6495ed";
  var femalePhdColor = "#ff0000";
  var unspecifiedColor = "#ff00ff";
  var unspecifiedPhdColor = "#000000";

  var configRepresentation = {
    type: 'line',
    data: {
      labels: labels,
      datasets: [{
	label: "Male",
	data: maleData,
	fill: false,
	backgroundColor: maleColor, borderColor: maleColor
      }, {
	label: "Female",
	data: femaleData,
	fill: false,
	backgroundColor: femaleColor, borderColor: femaleColor
      }, {
	label: "PhD Male",
	data: malePhdData,
	fill: false,
	backgroundColor: malePhdColor, borderColor: malePhdColor
      }, {
	label: "PhD Female",
	data: femalePhdData,
	fill: false,
	backgroundColor: femalePhdColor, borderColor: femalePhdColor
      }, {
	label: "Unspecified",
	data: unspecifiedData,
	fill: false,
	backgroundColor: unspecifiedColor, borderColor: unspecifiedColor
      }, {
	label: "PhD Unspecified",
	data: unspecifiedPhdData,
	fill: false,
	backgroundColor: unspecifiedPhdColor, borderColor: unspecifiedPhdColor
      } 
         ]},
    options: {
      responsive: true,
      title: {
	display: true,
	text: "PI Representation " + data.observatory.toUpperCase()
      },
      scales: {
	xAxes: [{
	  display: true,
	  scaleLabel: {
	    display: true,
	    labelString: "Semester"
	  }
	}],
	yAxes: [{
	  display: true,
	  scaleLabel: {
	    display: true,
	    labelString: "# People"
	  }
	}]
      }
    }
  };
  
  var repChart = new Chart(repPlotDiv, configRepresentation);

  var configSuccess = {
    type: 'line',
    data: {
      labels: labels,
      datasets: [{
	label: "Male",
	data: maleSuccessfulData,
	fill: false,
	backgroundColor: maleColor, borderColor: maleColor
      }, {
	label: "Female",
	data: femaleSuccessfulData,
	fill: false,
	backgroundColor: femaleColor, borderColor: femaleColor
      }, {
	label: "PhD Male",
	data: malePhdSuccessfulData,
	fill: false,
	backgroundColor: malePhdColor, borderColor: malePhdColor
      }, {
	label: "PhD Female",
	data: femalePhdSuccessfulData,
	fill: false,
	backgroundColor: femalePhdColor, borderColor: femalePhdColor
      }, {
	label: "Unspecified",
	data: unspecifiedSuccessfulData,
	fill: false,
	backgroundColor: unspecifiedColor, borderColor: unspecifiedColor
      }, {
	label: "PhD Unspecified",
	data: unspecifiedPhdSuccessfulData,
	fill: false,
	backgroundColor: unspecifiedPhdColor, borderColor: unspecifiedPhdColor
      }]},
    options: {
      responsive: true,
      title: {
	display: true,
	text: "PI Success Rate " + data.observatory.toUpperCase()
      },
      scales: {
	xAxes: [{
	  display: true,
	  scaleLabel: {
	    display: true,
	    labelString: "Semester"
	  }
	}],
	yAxes: [{
	  display: true,
	  scaleLabel: {
	    display: true,
	    labelString: "% People"
	  },
	  ticks: {
	    min: 0, max: 100
	  }
	}]
      }
    }
  };
  
  var successChart = new Chart(sucPlotDiv, configSuccess);

};

const fileLoaded = function(status, data) {
  //console.log(data);
  plotDiversity(data);
};

loadFile(atcaFile, fileLoaded);
loadFile(parkesFile, fileLoaded);
