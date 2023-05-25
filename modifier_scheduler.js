const localKey = "atnfSchedule";
const observatoryKey = "atnfObservatoryMod";
const semesterKey = "atnfSemesterMod";
const spath = "/cgi-bin/obstools/web_scheduler/scheduler.pl";
var authenticated = 0;
var observatoriesOrder = [];
var observatoriesObject = {};
var userstring;
var obs;
var semestersOrder = [];
var semestersObject = {};
var displayedSchedule = 0;
var schedulesLoaded = [];
var accumSlots = [];
var modSlotSelected = -1;
var serverSemesters = [];
var createdSemesters = {};

const projectTypeColours = {
    "Astro": "cdcdcd", "Maint": "cdcdff", "Config": "ffff8d",
    "BL": "ffcdff", "Training": "ff33e9", "Misc": "ff0000",
    "Space": "a215e8", "Purchased": "ffc000", "CABB": "ffcdcd"
};


const emptyDomNode = function(id) {
  var n = document.getElementById(id);
  
  if ((typeof n != "undefined") && (n != "undefined") &&
      (n != null)) {
    while (n.firstChild) {
      n.removeChild(n.firstChild);
    }
  }

  return n;
};

// Add one or more classes to a DOM element.
const domAddClasses = function(e, addClasses) {
  if ((typeof e == "undefined") || (e == "undefined") || (e == null)) {
    return;
  }
  
  // Do we want to add one or more classes?
  if ((typeof addClasses != "undefined") &&
      (addClasses != null)) {
    if (addClasses instanceof Array) {
      for (var i = 0; i < addClasses.length; i++) {
	if (!e.classList.contains(addClasses[i])) {
	  // This class is not yet there.
	  e.classList.add(addClasses[i]);
	}
      }
    } else {
      if (!e.classList.contains(addClasses)) {
	e.classList.add(addClasses);
      }
    }
  }
  
};

// Remove one or more classes to a DOM element.
const domRemoveClasses = function(e, removeClasses) {
  if ((typeof e == "undefined") || (e == "undefined") || (e == null)) {
    return;
  }

  // Do we want to remove one or more classes?
  if ((typeof removeClasses != "undefined") &&
      (removeClasses != null)) {
    if (removeClasses instanceof Array) {
      for (var i = 0; i < removeClasses.length; i++) {
	if (e.classList.contains(removeClasses[i])) {
	  e.classList.remove(removeClasses[i]);
	}
      }
    } else {
      if (e.classList.contains(removeClasses)) {
	e.classList.remove(removeClasses);
      }
    }
  }
  
};

// Convert degrees to radians.
const deg2rad = function(d) {
  return (d * Math.PI / 180);
};

// Convert radians to degrees.
const rad2deg = function(r) {
  return (r * 180 / Math.PI);
};

// Determine the LST limits for a source with RA,Dec.
// Given a Declination dec in degrees, a latitude lat in degrees,
// and an elevation el which is the limit, work out at which HA (in degrees)
// it would rise and set.
const haset_azel = function(dec, lat, el) {
  var decRad = deg2rad(dec);
  var latRad = deg2rad(lat);
  var elRad = deg2rad(el);
  var cos_haset = (Math.cos((Math.PI / 2) - elRad) -
		   Math.sin(latRad) * Math.sin(decRad)) /
      (Math.cos(decRad) * Math.cos(latRad));
  if (cos_haset > 1) {
    // The source never rises.
    return 0;
  }
  if (cos_haset < -1) {
    // The source never sets.
    return 180;
  }
  // Return the HA in degrees.
  return rad2deg(Math.acos(cos_haset));
};

// Zero pad a number to some level.
const zeroPadNumber = function(n, l) {
  var ll = 10;
  var s = "" + n;
  while ((ll <= l) && (n < ll)){
    s = "0" + s;
    ll *= 10;
  }
  return s;
};

const datetimeToString = function(d) {
  return d.getFullYear() + "-" +
    zeroPadNumber((d.getMonth() + 1), 10) + "-" +
    zeroPadNumber(d.getDate(), 10) + " " +
    zeroPadNumber(d.getHours(), 10) + ":" +
    zeroPadNumber(d.getMinutes(), 10) + ":" +
    zeroPadNumber(d.getSeconds(), 10);
};

// Do some number parsing.
const cleanjson = function(d) {
  if ((typeof d == "undefined") || (d == null)) {
    return null;
  }
  
  if ((d.hasOwnProperty("program")) &&
      (d.program.hasOwnProperty("project"))) {
    for (var i = 0; i < d.program.project.length; i++) {
      if (d.program.project[i].hasOwnProperty("slot")) {
	for (var j = 0; j < d.program.project[i].slot.length; j++) {
	  d.program.project[i].slot[j].rating = parseFloat(
	    d.program.project[i].slot[j].rating
	  );
	  d.program.project[i].slot[j].requested_duration = parseFloat(
	    d.program.project[i].slot[j].requested_duration
	  );
	}
      }
    }
  }

  return d;
};

// The the sexagesimal string s and convert it to degrees,
// noting if the string is actually in hours.
const stringToDegrees = function(s, inHours) {
  var sels = s.split(":");
  var isNeg = false;
  if (/^\-/.test(sels[0])) {
    isNeg = true;
  }
  var d = 0, m = 0, s = 0;
  
  d = Math.abs(parseInt(sels[0]));
  if (sels.length > 1) {
    m = parseInt(sels[1]);
  }
  if (sels.length > 2) {
    var s = parseFloat(sels[2]);
  }
  var n = d + m / 60.0 + s / 3600.0;
  if (isNeg) {
    n *= -1.0;
  }

  if (inHours) {
    n *= 15.0;
  }

  return n;
};

const degreesToString = function(d, inHours) {
    // We will only go to minutes in this function.
    var deg = d;

    if (deg < 0) {
	deg = 360.0 + deg;
    }
    if (deg >= 360) {
	deg -= 360.0;
    }
    
    
    if (inHours) {
	deg = deg / 15.0;
    }

    var wdeg = Math.floor(deg);
    var mdeg = Math.floor((deg - wdeg) * 60.0);
    var s = zeroPadNumber(wdeg, 10) + ":" + zeroPadNumber(mdeg, 10);
    return s;
}

// Get authenticated.
const getAuthenticated = function(callback) {
  // Check if we're online.
  if (!navigator.onLine) {
    // We assume we are authenticated, because if they don't have the
    // schedule beforehand it doesn't matter.
    authenticated = -1;
  } else {
    userstring = window.location.hash;
    if (userstring == "") {
      // No user string was given, so we check the local storage.
      userstring = window.localStorage.getItem("userstring");
    } else {
      // Get rid of the hash at the front.
      userstring = userstring.substring(1);
      // Save this in the local storage so we don't keep having to
      // supply it.
      window.localStorage.setItem("userstring", userstring);
    }
    if ((userstring != null) && (userstring != "")) {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', spath + "?request=authenticate&" +
	       "auth=" + userstring);
      xhr.responseType = "json";
      xhr.onload = function() {
	var status = xhr.status;
	if (status == 200) {
	  authenticated = xhr.response.authenticated;
	}
      }
      xhr.send();
    }
  }
  if (typeof callback != "undefined") {
    callback();
  } else {
    console.log("no callback specified to authentication routine");
  }
};


const fillObservatoryDetails = function() {
    // Get the selected observatory.
    var oe = document.getElementById("observatory");
    //console.log(oe.options);
    var obsSel = oe.options[oe.options.selectedIndex].value;
    if (obsSel == "new") {
	document.getElementById("observatoryName").value = "";
	document.getElementById("observatoryLongitude").value = "";
	document.getElementById("observatoryLatitude").value = "";
	document.getElementById("observatoryTimezoneHours").value = "";
	document.getElementById("observatoryTimezone").value = "";
	document.getElementById("observatoryElevationLimit").value = "";
    } else {
	document.getElementById("observatoryName").value =
	    observatoriesObject[obsSel].name;
	document.getElementById("observatoryShortName").value =
	    observatoriesObject[obsSel].shortName;
	document.getElementById("observatoryFullName").value =
	    observatoriesObject[obsSel].fullName;
	document.getElementById("observatoryLongitude").value =
	    observatoriesObject[obsSel].longitude;
	document.getElementById("observatoryLatitude").value =
	    observatoriesObject[obsSel].latitude;
	document.getElementById("observatoryTimezoneHours").value =
	    observatoriesObject[obsSel].timezoneDiffHours;
	document.getElementById("observatoryTimezone").value =
	    observatoriesObject[obsSel].timezoneLabel;
	document.getElementById("observatoryElevationLimit").value =
	    observatoriesObject[obsSel].elevationLimit;
    }
    obs = obsSel;
    window.localStorage.setItem(observatoryKey, obs);
};

const getTimeString = function(dateObject) {
  var dstring = dateObject.toISOString();
  return dstring.substring(0, 19).replace("T", " ");
};

const modificationTimeText = function(t) {
    var sdate = new Date(t * 1000);
    return getTimeString(sdate);
}

const setDefaultColour = function() {
    // We get called when the project type changes, and we change the
    // colour to the default for that project type.
    var ptype = document.getElementById("projectType").value;
    if (ptype == "ASTRO") {
	changeProjectColour(projectTypeColours.Astro);
    } else if (ptype == "MAINT") {
	changeProjectColour(projectTypeColours.Maint);
    } else if (ptype == "CONFIG") {
	changeProjectColour(projectTypeColours.Config);
    }
};

const setProjectType = function(type) {
    var pt = document.getElementById("projectType");
    if ((type == "ASTRO") || (type == "MAINT") || (type == "CONFIG") || (type == "NASA")) {
	pt.value = type;
	setDefaultColour();
    }
};

const accumulateProjectSlots = function(proj) {
    var slots = [];
    for (var i = 0; i < proj.slot.length; i++) {
	var slotFound = -1;
	for (var j = 0; j < slots.length; j++) {
	    if ((slots[j].slot.source == proj.slot[i].source) &&
		(slots[j].slot.requested_duration == proj.slot[i].requested_duration) &&
		(slots[j].slot.array == proj.slot[i].array) &&
		(slots[j].slot.bandwidth == proj.slot[i].bandwidth) &&
		(slots[j].slot.position.ra == proj.slot[i].position.ra) &&
		(slots[j].slot.position.dec == proj.slot[i].position.dec) &&
		(slots[j].slot.lst_start == proj.slot[i].lst_start) &&
		(slots[j].slot.lst_end == proj.slot[i].lst_end) &&
		(slots[j].slot.bands.length == proj.slot[i].bands.length) &&
		(slots[j].slot.bands.every((element, index) =>
					   element === proj.slot[i].bands[index]))) {
		// These are identical.
		slots[j].indices.push(i);
		slotFound = j;
		break;
	    }
	}
	if (slotFound == -1) {
	    // This is a new slot.
	    slots.push({ "slot": proj.slot[i], "indices": [ i ] });
	}
    }
    return slots;
}

const fillProjectElements = function() {
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    var ps = document.getElementById("projectSelect");
    
    scheduleLoaded.displayedProject = ps.options.selectedIndex;
    
    if (ps.options[scheduleLoaded.displayedProject].value == "New") {
	// Blank out all the boxes.
	document.getElementById("projectCode").value = "";
	document.getElementById("projectScore").value = "";
	document.getElementById("projectPISurname").value = "";
	document.getElementById("projectPIEmail").value = "";
	document.getElementById("projectTitle").value = "";
	document.getElementById("projectComments").value = "";
	setProjectType("ASTRO");
	emptyDomNode("slotModifySelect");
	document.getElementById("addSlotSourceName").value = "";
	document.getElementById("addSlotRA").value = "";
	document.getElementById("addSlotDec").value = "";
	document.getElementById("addSlotLSTStart").value = "";
	document.getElementById("addSlotLSTEnd").value = "";
	document.getElementById("addSlotBands").value = "";
	document.getElementById("addSlotBandwidth").value = "";
	document.getElementById("addSlotDuration").value = "";
	document.getElementById("addSlotConfig").value = "";
	document.getElementById("addSlotNumSlots").value = "";
	document.getElementById("modifySlotSourceName").value = "";
	document.getElementById("modifySlotRA").value = "";
	document.getElementById("modifySlotDec").value = "";
	document.getElementById("modifySlotLSTStart").value = "";
	document.getElementById("modifySlotLSTEnd").value = "";
	document.getElementById("modifySlotBands").value = "";
	document.getElementById("modifySlotBandwidth").value = "";
	document.getElementById("modifySlotDuration").value = "";
	document.getElementById("modifySlotConfig").value = "";
	document.getElementById("modifySlotNumSlots").value = "";
	
    } else {
	var project = scheduleLoaded.schedule.program.project[scheduleLoaded.displayedProject];
	// Set all the boxes.
	document.getElementById("projectCode").value =
	    project.ident;
	document.getElementById("projectScore").value =
	    project.slot[0].rating;
	document.getElementById("projectPISurname").value =
	    project.PI;
	document.getElementById("projectPIEmail").value =
	    project.PI_email;
	document.getElementById("projectTitle").value =
	    project.title;
	document.getElementById("projectComments").value =
	    project.comments;
	setProjectType(project.type);
	changeProjectColour(project.colour);
	// Accumulate the slots.
	accumSlots = accumulateProjectSlots(project);
	var ss = document.getElementById("slotModifySelect");
	emptyDomNode("slotModifySelect");
	for (var i = 0; i < accumSlots.length; i++) {
	    var o = document.createElement("option");
	    o.setAttribute("value", i);
	    if (modSlotSelected == i) {
		o.setAttribute("selected", "selected");
		modSlotSelected = -1;
	    }
	    o.innerHTML = accumSlots[i].slot.source;
	    ss.appendChild(o);
	}
	slotSelectionHandler();
    }
};

const slotSelectionHandler = function() {
    var ss = document.getElementById("slotModifySelect");
    var so = ss.selectedOptions;
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    var project = scheduleLoaded.schedule.program.project[scheduleLoaded.displayedProject];

    if (so.length == 1) {
	// Fill the boxes.
	var slotDetails = accumSlots[so[0].value].slot;
	document.getElementById("modifySlotSourceName").value = slotDetails.source;
	document.getElementById("modifySlotRA").value = slotDetails.position.ra;
	document.getElementById("modifySlotDec").value = slotDetails.position.dec;
	document.getElementById("modifySlotLSTStart").value = slotDetails.lst_start;
	document.getElementById("modifySlotLSTEnd").value = slotDetails.lst_end;
	document.getElementById("modifySlotBands").value = slotDetails.bands.join(",");
	document.getElementById("modifySlotBandwidth").value = slotDetails.bandwidth;
	document.getElementById("modifySlotDuration").value = slotDetails.requested_duration;
	document.getElementById("modifySlotConfig").value = slotDetails.array;
	document.getElementById("modifySlotNumSlots").value = accumSlots[so[0].value].indices.length;

	// Display the slot summaries.
	emptyDomNode("slotDisplayTable");
	for (var i = 0; i < accumSlots[so[0].value].indices.length; i++) {
	    var si = accumSlots[so[0].value].indices[i];
	    var tr = document.createElement("tr");
	    var td = document.createElement("td");
	    td.innerHTML = (i + 1);
	    tr.appendChild(td);
	    td = document.createElement("td");
	    td.innerHTML = project.slot[si].source;
	    tr.appendChild(td);
	    td = document.createElement("td");
	    td.innerHTML = project.slot[si].scheduled_duration;
	    tr.appendChild(td);
	    td = document.createElement("td");
	    if (project.slot[si].scheduled == 0) {
		td.innerHTML = "N/A";
	    } else {
		var st = new Date(project.slot[si].scheduled_start * 1000);
		td.innerHTML = datetimeToString(st);
	    }
	    tr.appendChild(td);
	    td = document.createElement("td");
	    if (project.slot[si].scheduled == 0) {
		td.innerHTML = "N/A";
	    } else {
		var et = new Date(project.slot[si].scheduled_start * 1000 +
				  project.slot[si].scheduled_duration * 3600 * 1000);
		td.innerHTML = datetimeToString(et);
	    }
	    tr.appendChild(td);
	    document.getElementById("slotDisplayTable").appendChild(tr);
	}
    } else {
	// Empty the boxes.
	document.getElementById("modifySlotSourceName").value = "";
	document.getElementById("modifySlotRA").value = "";
	document.getElementById("modifySlotDec").value = "";
	document.getElementById("modifySlotLSTStart").value = "";
	document.getElementById("modifySlotLSTEnd").value = "";
	document.getElementById("modifySlotBands").value = "";
	document.getElementById("modifySlotBandwidth").value = "";
	document.getElementById("modifySlotDuration").value = "";
	document.getElementById("modifySlotConfig").value = "";
	document.getElementById("modifySlotNumSlots").value = "";
	
    }
}

const fillScheduleElements = function() {
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    
    // Fill in the modify term row.
    document.getElementById("termName").value =
	scheduleLoaded.schedule.program.term.term;
    document.getElementById("termStartDate").value =
	scheduleLoaded.schedule.program.term.start;
    document.getElementById("termEndDate").value =
	scheduleLoaded.schedule.program.term.end;
    var firstConfig = "None";
    var configOwner = "Nobody";
    for (var i = 0; i < scheduleLoaded.schedule.program.project.length; i++) {
	if (scheduleLoaded.schedule.program.project[i].ident == "CONFIG") {
	    firstConfig = scheduleLoaded.schedule.program.project[i].slot[0].array.toUpperCase();
	    configOwner = scheduleLoaded.schedule.program.project[i].PI;
	    break;
	}
    }
    document.getElementById("termFirstConfig").value = firstConfig;
    document.getElementById("termConfigOwner").value = configOwner;

    // Fill in the statistics row.
    document.getElementById("currentSchedule").innerHTML =
	scheduleLoaded.schedule.program.observatory.observatory + " " +
	scheduleLoaded.schedule.program.term.term;
    document.getElementById("scheduleModificationTime").innerHTML =
	modificationTimeText(scheduleLoaded.modTime);
    document.getElementById("scheduleNumModifications").innerHTML =
	scheduleLoaded.numModifications;

    // Make the project selector.
    var ps = document.getElementById("projectSelect");
    emptyDomNode("projectSelect");
    for (var i = 0; i < scheduleLoaded.schedule.program.project.length; i++) {
	var o = document.createElement("option");
	o.setAttribute("value", scheduleLoaded.schedule.program.project[i].ident);
	if (i == scheduleLoaded.displayedProject) {
	    o.setAttribute("selected", "selected");
	}
	o.innerHTML = scheduleLoaded.schedule.program.project[i].ident;
	ps.appendChild(o);
    }
    // Add a "New" project.
    var o = document.createElement("option");
    o.setAttribute("value", "New");
    o.innerHTML = "New";
    ps.appendChild(o);
};

const makeScheduleModification = function(scheduleLoaded) {
    scheduleLoaded.numModifications += 1;
    var n = new Date();
    scheduleLoaded.schedule.modificationTime = n.getTime() / 1000;
    scheduleLoaded.modTime = scheduleLoaded.schedule.modificationTime;
    fillScheduleElements();
    fillProjectElements();
};

const saveCurrentSchedule = function(scheduleLoaded) {
    var csched = JSON.stringify(scheduleLoaded);
    scheduleLoaded.previous = csched;
};

const undoScheduleModification = function() {
    if ((schedulesLoaded[displayedSchedule].numModifications > 0) &&
	(schedulesLoaded[displayedSchedule].previous != "")) {
	var psched = JSON.parse(schedulesLoaded[displayedSchedule].previous);
	schedulesLoaded[displayedSchedule] = psched;
	fillScheduleElements();
	fillProjectElements();
    }
};
      
const loadFile = function() {
    if (authenticated == 0) {
	return;
    }
    // Get the observatory and semester that is selected.
    var termObs = document.getElementById("termObservatory");
    var termTerm = document.getElementById("termSelect");
    var tobs = termObs.options[termObs.options.selectedIndex].value;
    var tterm = termTerm.options[termTerm.options.selectedIndex].value;

    if (tterm == "New") {
	// We can't load anything, but we blank out the boxes.
	document.getElementById("termName").value = "";
	document.getElementById("termStartDate").value = "";
	document.getElementById("termEndDate").value = "";
	document.getElementById("termFirstConfig").value = "";
	document.getElementById("termConfigOwner").value = "";

	// Clear all the other boxes as well.
	emptyDomNode("projectSelect");
	document.getElementById("projectCode").value = "";
	document.getElementById("projectScore").value = "";
	document.getElementById("projectPISurname").value = "";
	document.getElementById("projectPIEmail").value = "";
	document.getElementById("projectTitle").value = "";
	document.getElementById("projectType").value = "ASTRO";
	projectTypeChanged();
	document.getElementById("projectComments").value = "";

	document.getElementById("addSlotSourceName").value = "";
	document.getElementById("addSlotRA").value = "";
	document.getElementById("addSlotDec").value = "";
	document.getElementById("addSlotLSTStart").value = "";
	document.getElementById("addSlotLSTEnd").value = "";
	document.getElementById("addSlotBands").value = "";
	document.getElementById("addSlotBandwidth").value = "";
	document.getElementById("addSlotDuration").value = "";
	document.getElementById("addSlotConfig").value = "";
	document.getElementById("addSlotNumSlots").value = "";
	emptyDomNode("slotModifySelect");
	document.getElementById("modifySlotSourceName").value = "";
	document.getElementById("modifySlotRA").value = "";
	document.getElementById("modifySlotDec").value = "";
	document.getElementById("modifySlotLSTStart").value = "";
	document.getElementById("modifySlotLSTEnd").value = "";
	document.getElementById("modifySlotBands").value = "";
	document.getElementById("modifySlotBandwidth").value = "";
	document.getElementById("modifySlotDuration").value = "";
	document.getElementById("modifySlotConfig").value = "";
	document.getElementById("modifySlotNumSlots").value = "";

	return;
    }

    // Check if we already have a cached version of the required schedule.
    for (var i = 0; i < schedulesLoaded.length; i++) {
	if ((schedulesLoaded[i].schedule.program.term.term == tterm) &&
	    (schedulesLoaded[i].schedule.program.observatory.observatory == tobs)) {
	    displayedSchedule = i;
	    fillScheduleElements();
	    fillProjectElements();
	    return;
	}
    }
    
    var xhr = new XMLHttpRequest();
    var gstring = "?request=load&observatory=" + tobs +
	"&term=" + tterm;
    xhr.open('GET', spath + gstring, true);
    xhr.responseType = "json";
    xhr.onload = function() {
	var status = xhr.status;
	if (status == 200) {
	    var scheduleLoaded = cleanjson(xhr.response);
	    // Add it to the list.
	    schedulesLoaded.push({ "schedule": scheduleLoaded,
				   "numModifications": 0,
				   "modTime": scheduleLoaded.modificationTime,
				   "previous": "",
				   "displayedProject": 0 });
	    displayedSchedule = schedulesLoaded.length - 1;
	    fillScheduleElements();
	    fillProjectElements();
	}
    }
    xhr.send();

};

const addSemesters = function(schedobs, toselect) {
    var ts = document.getElementById("termSelect");
    emptyDomNode("termSelect");

    // We add any newly created terms first.
    if (createdSemesters.hasOwnProperty(schedobs)) {
	for (var i = 0; i < createdSemesters[schedobs].length; i++) {
	    var o = document.createElement("option");
	    o.setAttribute("value", createdSemesters[schedobs][i]);
	    o.innerHTML = createdSemesters[schedobs][i];
	    if (createdSemesters[schedobs][i] == toselect) {
		o.setAttribute("selected", "selected");
	    }
	    ts.appendChild(o);
	}
    }
    
    for (var i = 0; i < serverSemesters.length; i++) {
	var o = document.createElement("option");
	o.setAttribute("value", serverSemesters[i]);
	o.innerHTML = serverSemesters[i];
	if (serverSemesters[i] == toselect) {
	    o.setAttribute("selected", "selected");
	}
	ts.appendChild(o);
    }

    // Now add a "new" entry.
    var o = document.createElement("option");
    o.setAttribute("value", "New");
    o.innerHTML = "New";
    ts.appendChild(o);
	
    // Now load the schedule.
    loadFile();
};

const getSemesterList = function() {
    // We try to get the list of all the semesters on the server for
    // the selected observatory.
    var oe = document.getElementById("termObservatory");
    var obsSel = oe.options[oe.options.selectedIndex].value;
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', spath + "?request=listsemesters&" +
	     "observatory=" + obsSel, true);
    xhr.responseType = "json";
    xhr.onload = function() {
	var status = xhr.status;
	if (status == 200) {
	    var asem = xhr.response.semesters;
	    asem.sort();
	    asem.reverse();
	    serverSemesters = asem;
	} else {
	    console.log("failure while getting list of semesters for " +
			obsSel);
	}
	addSemesters(obsSel, "");
    };

    xhr.send();
};

const modifyObservatoryHandler = function() {
    var oe = document.getElementById("observatory");
    var obsSel = oe.options[oe.options.selectedIndex].value;

    if ((obsSel == "atca") || (obsSel == "parkes")) {
	// Don't allow changing of these observatories.
	console.log("Unable to change ATNF observatory details!");
	return;
    }

    // Update the JSON before we send it.
    var obsj =
	{ 
	    "name": document.getElementById("observatoryName").value,
	    "shortName": document.getElementById("observatoryShortName").value,
	    "fullName": document.getElementById("observatoryFullName").value,
	    "longitude": parseFloat(document.getElementById("observatoryLongitude").value),
	    "latitude": parseFloat(document.getElementById("observatoryLatitude").value),
	    "timezoneDiffHours": parseFloat(document.getElementById("observatoryTimezoneHours").value),
	    "timezoneLabel": document.getElementById("observatoryTimezone").value,
	    "elevationLimit": parseFloat(document.getElementById("observatoryElevationLimit").value)
	};

    // Check if all things are present.
    var usable = true;
    if (obsj.name == "") {
	usable = false;
	domAddClasses(document.getElementById("observatoryName"),
		      "inputError");
    }
    if (obsj.shortName == "") {
	usable = false;
	domAddClasses(document.getElementById("observatoryShortName"),
		      "inputError");
    }
    if (obsj.fullName == "") {
	usable = false;
	domAddClasses(document.getElementById("observatoryFullName"),
		      "inputError");
    }
    if (document.getElementById("observatoryLongitude").value == "") {
	usable = false;
	domAddClasses(document.getElementById("observatoryLongitude"),
		      "inputError");
    }
    if (document.getElementById("observatoryLatitude").value == "") {
	usable = false;
	domAddClasses(document.getElementById("observatoryLatitude"),
		      "inputError");
    }
    if (document.getElementById("observatoryTimezoneHours").value == "") {
	usable = false;
	domAddClasses(document.getElementById("observatoryTimezoneHours"),
		      "inputError");
    }
    if (obsj.timezoneLabel == "") {
	usable = false;
	domAddClasses(document.getElementById("observatoryTimezone"),
		      "inputError");
    }
    if (document.getElementById("observatoryElevationLimit").value == "") {
	usable = false;
	domAddClasses(document.getElementById("observatoryElevationLimit"),
		      "inputError");
    }
    if (usable == false) {
	return;
    }
    
    if (obsSel == "new") {
	// This is a new observatory.
	obsj.id = document.getElementById("observatoryName").value.toLowerCase();
	observatoriesOrder.push(obsj.id);
    } else {
	obsj.id = obsSel;
    }
    console.log(obsj);
    observatoriesObject[obsj.id] = obsj;
    obs = obsj.id;
    window.localStorage.setItem(observatoryKey, obs);

    // We make a new array with all the observatories.
    var obsarr = [];
    for (var i = 0; i < observatoriesOrder.length; i++) {
	obsarr.push(observatoriesObject[observatoriesOrder[i]]);
    }
    var outobj = { "observatories": obsarr };
    var xhr = new XMLHttpRequest();
    xhr.open("POST", spath, true);
    xhr.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
    xhr.responseType = "json";
    xhr.onload = function() {
	var status = xhr.status;
	if (status == 200) {
	    console.log("observatories list updated");
	    getObservatoryList();
	} else {
	    console.log("error while updating observatories list");
	}
    }
    var sstring = "request=updateObservatories&auth=" + userstring +
	"&observatories=" + JSON.stringify(obsarr);
    xhr.send(sstring);
};

const getObservatoryList = function() {
    // The list of observatories on the page.
    var oe = document.getElementById("observatory");
    var oet = document.getElementById("termObservatory");
    var sobs = window.localStorage.getItem(observatoryKey);
    
    // Go to the server and ask for the list of possible observatories.
    var xhr = new XMLHttpRequest();
    xhr.open('GET', spath + "?request=listobservatories", true);
    xhr.responseType = "json";
    xhr.onload = function() {
	var status = xhr.status;
	if (status == 200) {
	    emptyDomNode("observatory");
	    var observatories = xhr.response.observatories;
	    obs = observatories[0].id;
	    for (var i = 0; i < observatories.length; i++) {
		observatoriesObject[observatories[i].id] = observatories[i];
		observatoriesOrder.push(observatories[i].id);
		var o = document.createElement("option");
		var ot = document.createElement("option");
		o.setAttribute("value", observatories[i].id);
		o.innerHTML = observatories[i].name;
		ot.setAttribute("value", observatories[i].id);
		ot.innerHTML = observatories[i].name;
		if (observatories[i].id == sobs) {
		    o.setAttribute("selected", "selected");
		    ot.setAttribute("selected", "selected");
		    obs = sobs;
		}
		oe.appendChild(o);
		oet.appendChild(ot);
	    }
	    // Add an entry for a new observatory.
	    var o = document.createElement("option");
	    o.setAttribute("value", "new");
	    o.innerHTML = "New";
	    oe.appendChild(o);
	    // We now find the semester for this observatory.
	    fillObservatoryDetails();
	    getSemesterList();
	    //checkServerTime(getSemester);
	} else {
	    console.log("failure while getting list of observatories");
	}
    }
    xhr.send();

};

const slotModifier = function() {
    var ss = document.getElementById("slotModifySelect");
    var so = ss.selectedOptions;
    if (so.length != 1) {
	// Can't do it.
	return;
    }

    modSlotSelected = so[0].value;
    var slotDetails = accumSlots[so[0].value];
    // Change the details.
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    var project = scheduleLoaded.schedule.program.project[scheduleLoaded.displayedProject];

    saveCurrentSchedule(scheduleLoaded);
    
    // Check if we are modifying the number of slots.
    var newNumSlots = parseInt(document.getElementById("modifySlotNumSlots").value);
    if (newNumSlots < 1) {
	newNumSlots = 1;
    }
    if (newNumSlots > slotDetails.indices.length) {
	// We are adding more of this slot.
	while (slotDetails.indices.length < newNumSlots) {
	    var nslot = JSON.parse(JSON.stringify(slotDetails.slot));
	    nslot.scheduled = 0;
	    nslot.scheduled_duration = 0;
	    nslot.start_time = 0;
	    project.slot.push(nslot);
	    slotDetails.indices.push(project.slot.length - 1);
	}
    } else if (newNumSlots < slotDetails.indices.length) {
	// We are removing some of these slots, but we can only do that if
	// the slot has not been scheduled.
	var slotsToDelete = [];
	var numToDelete = slotDetails.indices.length - newNumSlots;
	for (var i = 0; i < slotDetails.indices.length; i++) {
	    if (slotsToDelete.length == numToDelete) {
		break;
	    }
	    if (project.slot[slotDetails.indices[i]].scheduled == 0) {
		slotsToDelete.push(slotDetails.indices[i]);
	    }
	}
	// Sort the indices into descending order.
	slotsToDelete.sort(function(a, b) { return b - a; });
	for (var i = 0; i < slotsToDelete.length; i++) {
	    // Remove the slot.
	    project.slot.splice(slotsToDelete[i], 1);
	    // Adjust the indices in the project.
	    for (var j = 0; j < slotDetails.indices.length; j++) {
		if (slotDetails.indices[j] > slotsToDelete[i]) {
		    slotDetails.indices[j] -= 1;
		}
	    }
	    // And remove the index.
	    slotDetails.indices.splice(slotDetails.indices.indexOf(slotsToDelete[i]), 1);
	}
    }

    // Change each slot to match the new details.
    for (var i = 0; i < slotDetails.indices.length; i++) {
	project.slot[slotDetails.indices[i]].source =
	    document.getElementById("modifySlotSourceName").value;
	project.slot[slotDetails.indices[i]].position.ra =
	    document.getElementById("modifySlotRA").value;
	project.slot[slotDetails.indices[i]].position.dec =
	    document.getElementById("modifySlotDec").value;
	project.slot[slotDetails.indices[i]].lst_start =
	    document.getElementById("modifySlotLSTStart").value;
	project.slot[slotDetails.indices[i]].lst_end =
	    document.getElementById("modifySlotLSTEnd").value;
	project.slot[slotDetails.indices[i]].bands =
	    document.getElementById("modifySlotBands").value.split(",");
	project.slot[slotDetails.indices[i]].bandwidth =
	    document.getElementById("modifySlotBandwidth").value;
	project.slot[slotDetails.indices[i]].requested_duration =
	    parseInt(document.getElementById("modifySlotDuration").value);
	project.slot[slotDetails.indices[i]].array =
	    document.getElementById("modifySlotConfig").value;
    }
    makeScheduleModification(scheduleLoaded);
    
};

const projectDeleter = function() {
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    var project = scheduleLoaded.schedule.program.project[scheduleLoaded.displayedProject];

    if ((project.ident == "CONFIG") || (project.ident == "MAINT")) {
	// Can't delete these projects.
	console.log("can't delete config or maintenance project");
	return;
    }

    saveCurrentSchedule(scheduleLoaded);
    scheduleLoaded.schedule.program.project.splice(scheduleLoaded.displayedProject, 1);
    makeScheduleModification(scheduleLoaded);
};

const slotDeleter = function() {
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    var project = scheduleLoaded.schedule.program.project[scheduleLoaded.displayedProject];

    var ss = document.getElementById("slotModifySelect");
    var so = ss.selectedOptions;
    var si = Array.from(so).map(o => parseInt(o.value));
    if (si.length == ss.options.length) {
	// This is all the slots, so we can't do that.
	console.log("can't delete all slots");
	return;
    }
    var slotIndices = [];
    for (var i = 0; i < si.length; i++) {
	for (var j = 0; j < accumSlots[si[i]].indices.length; j++) {
	    slotIndices.push(accumSlots[si[i]].indices[j]);
	}
    }
    slotIndices.sort(function(a, b) { return (b - a) });

    if (slotIndices.length > 0) {
	saveCurrentSchedule(scheduleLoaded);
    }
    for (var i = 0; i < slotIndices.length; i++) {
	project.slot.splice(slotIndices[i], 1);
    }
    makeScheduleModification(scheduleLoaded);
};

const slotAdder = function() {
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    var project = scheduleLoaded.schedule.program.project[scheduleLoaded.displayedProject];

    var numToAdd = parseInt(document.getElementById("addSlotNumSlots").value);
    if (numToAdd > 0) {
	var usable = true;
	var source = document.getElementById("addSlotSourceName").value;
	if (source == "") {
	    // Can't add this.
	    usable = false;
	    domAddClasses(document.getElementById("addSlotSourceName"),
			  "inputError");
	}
	var ra = document.getElementById("addSlotRA").value;
	if (ra == "") {
	    usable = false;
	    domAddClasses(document.getElementById("addSlotRA"),
			  "inputError");
	}
	var dec = document.getElementById("addSlotDec").value;
	if (dec == "") {
	    usable = false;
	    domAddClasses(document.getElementById("addSlotDec"),
			  "inputError");
	}
	var bandst = document.getElementById("addSlotBands").value;
	var bands = [];
	if (bandst != "") {
	    bands = bandst.split(",");
	}
	var bandwidth = document.getElementById("addSlotBandwidth").value;
	var config = document.getElementById("addSlotConfig").value;
	if (config == "") {
	    usable = false;
	    domAddClasses(document.getElementById("addSlotConfig"),
			  "inputError");
	}
	
	var duration = parseFloat(document.getElementById("addSlotDuration").value);
	if ((duration == "") || (duration < 0)) {
	    usable = false;
	    domAddClasses(document.getElementById("addSlotDuration"),
			  "inputError");
	}
	if (usable == false) {
	    return;
	}

	var lstStart = document.getElementById("addSlotLSTStart").value;
	var lstEnd = document.getElementById("addSlotLSTEnd").value;
	if ((lstStart == "") || (lstEnd == "")) {
	    // Calculate the LST limits for the user from the RA and Dec.
	    var ra_degrees = stringToDegrees(ra, true);
	    var dec_degrees = stringToDegrees(dec, false);
	    console.log(ra_degrees + " " + dec_degrees);
	    var haset = haset_azel(dec_degrees,
				   observatoriesObject[obs].latitude,
				   observatoriesObject[obs].elevationLimit);
	    console.log(haset);
	    var riseDeg = (ra_degrees - haset);
	    var setDeg = (ra_degrees + haset);
	    console.log(riseDeg + " " + setDeg);
	    lstStart = degreesToString(riseDeg, true);
	    lstEnd = degreesToString(setDeg, true);
	}
	
	saveCurrentSchedule(scheduleLoaded);
	for (var i = 0; i < numToAdd; i++) {
	    var ob = {
		"source": source, "array": config,
		"scheduled": 0, "scheduled_duration": 0,
		"scheduled_start": 0, "lst_start": lstStart,
		"lst_end": lstEnd, "requested_duration": duration,
		"bands": bands,
		"bandwidth": bandwidth,
		"rating": parseFloat(document.getElementById("projectScore").value),
		"lst_limits_used": 0, "position": { "ra": ra, "dec": dec } };
	    project.slot.push(ob);
	}
	
    } else {
	domAddClasses(document.getElementById("addSlotNumSlots"),
		      "inputError");
	return;
    }
    makeScheduleModification(scheduleLoaded);
};

const changeProjectColour = function(colourCode) {
    var pcs = document.getElementById("projectColourStandard");
    var valueSet = false;
    for (const t in projectTypeColours) {
	if (colourCode == projectTypeColours[t]) {
	    pcs.value = colourCode;
	    valueSet = true;
	    break;
	}
    }
    if (valueSet == false) {
	pcs.value = "other";
    }
    // Now set the colour input box and the colour of the row.
    document.getElementById("projectColour").value = colourCode;
    document.getElementById("projectModifyRow").setAttribute("style",
							     "background-color:#" + colourCode + ";");
};

const projectTypeChanged = function() {
    // We get called if the project type has changed.
    // We change the colour to the default for the new type.
    var pt = document.getElementById("projectType").value;
    setProjectType(pt);
};

const colourSelectChanged = function() {
    // We get called if the user has changed the colour selection box.
    var pcs = document.getElementById("projectColourStandard").value;
    if (pcs != "other") {
	changeProjectColour(pcs);
    } else {
	changeProjectColour("ffffff");
    }
};

const colourBoxChanged = function() {
    // We get called if the user has changed the colour description box.
    var pc = document.getElementById("projectColour").value;
    changeProjectColour(pc);
};

const projectModifier = function() {
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    var project = scheduleLoaded.schedule.program.project[scheduleLoaded.displayedProject];

    // Set the values according to the new set.
    var ps = document.getElementById("projectSelect").value;
    var changeMade = false;
    var changePossible = true;
    var pcode = document.getElementById("projectCode").value;
    if (pcode == "") {
	changePossible = false;
	domAddClasses(document.getElementById("projectCode"),
		      "inputError");
    }
    var pscore = parseFloat(document.getElementById("projectScore").value);
    if (pscore < 0) {
	changePossible = false;
	domAddClasses(document.getElementById("projectScore"),
		      "inputError");
    }
    var psurname = document.getElementById("projectPISurname").value;
    if (psurname == "") {
	changePossible = false;
	domAddClasses(document.getElementById("projectPISurname"),
		      "inputError");
    }
    var pemail = document.getElementById("projectPIEmail").value;
    if (pemail == "") {
	changePossible = false;
	domAddClasses(document.getElementById("projectPIEmail"),
		      "inputError");
    }
    var ptitle = document.getElementById("projectTitle").value;
    if (ptitle == "") {
	changePossible = false;
	domAddClasses(document.getElementById("projectTitle"),
		      "inputError");
    }
    var ptype = document.getElementById("projectType").value;
    var pcolour = document.getElementById("projectColour").value;
    if (pcolour == "") {
	pcolour = projectTypeColours.Astro;
    }
    var pcomments = document.getElementById("projectComments").value;
    
    if (changePossible == false) {
	return;
    }
    var jic = scheduleLoaded.previous;
    saveCurrentSchedule(scheduleLoaded);
    
    if (ps != "New") {
	// We may have to make a modification.
	if ((pcode != project.ident) &&
	    (project.ident != "MAINT") &&
	    (project.ident != "CONFIG")) {
	    changeMade = true;
	    project.ident = pcode;
	}
	for (var i = 0; i < project.slot.length; i++) {
	    if (pscore != project.slot[i].rating) {
		changeMade = true;
		project.slot[i].rating = pscore;
	    }
	}
	if (psurname != project.PI) {
	    changeMade = true;
	    project.PI = psurname;
	}
	if (pemail != project.PI_email) {
	    changeMade = true;
	    project.PI_email = pemail;
	}
	if (ptitle != project.title) {
	    changeMade = true;
	    project.title = ptitle;
	}
	if (ptype != project.type) {
	    changeMade = true;
	    project.type = ptype;
	}
	if (pcolour != project.colour) {
	    changeMade = true;
	    project.colour = pcolour;
	}
	if (pcomments != project.comments) {
	    changeMade = true;
	    project.comments = pcomments;
	}
    } else {
	// This is a new project.
	project = scheduleLoaded.schedule.program.project;
	var nproj = {
	    "PI": psurname, "PI_email": pemail,
	    "PI_affiliation": "CASS", "PI_country": "Australia",
	    "coI_affiliations": [], "coI_countries": [],
	    "coI_emails": [], "co_investigators": [],
	    "colour": pcolour, "comments": pcomments,
	    "excluded_dates": [], "help_required": "None",
	    "ident": pcode, "preferred_dates": "",
	    "prefers_nights": 0, "title": ptitle,
	    "type": ptype, "slot": [ {
		"source": "default", "array": "any",
		"scheduled": 0, "scheduled_duration": 0,
		"scheduled_start": 0, "lst_start": "00:00",
		"lst_end": "23:59", "requested_duration": 12,
		"bands":[], "bandwidth": "", "rating": pscore,
		"lst_limits_used": 0,
		"position": { "ra": "00:00:00", "dec": "-90:00:00" }
	    } ]
	};
	project.push(nproj);
	changeMade = true;
    }
    if (changeMade == true) {
	makeScheduleModification(scheduleLoaded);
    } else {
	scheduleLoaded.previous = jic;
    }
};

const termModifier = function() {
    // We get called when the user wants to change a term or make a new one.
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    
    var ts = document.getElementById("termSelect").value;
    var modificationPossible = true;
    var termName = document.getElementById("termName").value;
    if (termName == "") {
	modificationPossible = false;
	domAddClasses(document.getElementById("termName"),
		      "inputError");
    }
    var termStartDate = document.getElementById("termStartDate").value;
    if (termStartDate == "") {
	modificationPossible = false;
	domAddClasses(document.getElementById("termStartDate"),
		      "inputError");
    }
    var termEndDate = document.getElementById("termEndDate").value;
    if (termEndDate == "") {
	modificationPossible = false;
	domAddClasses(document.getElementById("termEndDate"),
		      "inputError");
    }
    var termFirstConfig = document.getElementById("termFirstConfig").value;
    if (termFirstConfig == "") {
	modificationPossible = false;
	domAddClasses(document.getElementById("termFirstConfig"),
		      "inputError");
    }
    var termConfigOwner = document.getElementById("termConfigOwner").value;
    if (termConfigOwner == "") {
	modificationPossible = false;
	domAddClasses(document.getElementById("termConfigOwner"),
		      "inputError");
    }
    if (modificationPossible == false) {
	return;
    }
    if (ts != "New") {
	var program = scheduleLoaded.schedule.program;
	// We are modifying the term.
	var modificationRequired = false;
	if (termName != program.term.term) {
	    modificationRequired = true;
	}
	if (termStartDate != program.term.start) {
	    modificationRequired = true;
	}
	if (termEndDate != program.term.end) {
	    modificationRequired = true;
	}
	var configIndex = -1;
	for (var i = 0; i < program.project.length; i++) {
	    if (program.project[i].ident == "CONFIG") {
		configIndex = i;
		break;
	    }
	}
	if (termFirstConfig != program.project[configIndex].slot[0].array) {
	    modificationRequired = true;
	}
	if (termConfigOwner != program.project[configIndex].PI) {
	    modificationRequired = true;
	}

	if (modificationPossible && modificationRequired) {
	    saveCurrentSchedule(scheduleLoaded);
	    program.term.term = termName;
	    program.term.start = termStartDate;
	    program.term.end = termEndDate;
	    program.project[configIndex].slot[0].array = termFirstConfig;
	    program.project[configIndex].PI = termConfigOwner;
	    makeScheduleModification(scheduleLoaded);
	}
    } else {
	// We're making a new term.
	var n = new Date();
	var nterm = {
	    "modificationTime": n.getTime() / 1000,
	    "program": {
		"colours": { "default": "cdcdcd", "unscheduled": "9ae68d",
			     "outsideSemester": "ffcdcd" },
		"observatory": {
		    "observatory": document.getElementById("termObservatory").value
		}, "releasedates": {}, "special": {}, "term": {
		    "configs": [], "term": termName, "start": termStartDate,
		    "end": termEndDate, "version": 1
		}, "project": [ {
		    "PI": termConfigOwner, "PI_affiliation": "CASS",
		    "PI_country": "Australia", "PI_email": termConfigOwner,
		    "coI_affiliations": [], "coI_countries": [], "coI_emails": [],
		    "co_investigators": [], "colour": projectTypeColours.Config,
		    "comments": "", "excluded_dates": [], "help_required": "None",
		    "ident": "CONFIG", "preferred_dates": "", "prefers_night": 0,
		    "title": "Reconfig",
		    "slot": [ {
			"array": termFirstConfig, "bands": [], "bandwidth": "",
			"lst_start": "00:00", "lst_end": "23:59", "lst_limits_used": 0,
			"position": { "ra": "00:00:00", "dec": "-90:00:00" },
			"rating": 6.0, "requested_duration": 24, "scheduled": 0,
			"scheduled_duration": 0, "scheduled_start": 0,
			"source": termFirstConfig,
		    } ] }, {
			"PI": termConfigOwner, "PI_affiliation": "CASS",
			"PI_country": "Australia", "PI_email": termConfigOwner,
			"coI_affiliations": [], "coI_countries": [], "coI_emails": [],
			"co_investigators": [], "colour": projectTypeColours.Maint,
			"comments": "", "excluded_dates": [], "help_required": "None",
			"ident": "MAINT", "preferred_dates": "", "prefers_night": 0,
			"title": "Maintenance/Test",
			"slot": [ {
			    "array": "any", "bands": [], "bandwidth": "",
			    "lst_start": "00:00", "lst_end": "23:59", "lst_limits_used": 0,
			    "position": { "ra": "00:00:00", "dec": "-90:00:00" },
			    "rating": 6.0, "requested_duration": 8, "scheduled": 0,
			    "scheduled_duration": 0, "scheduled_start": 0,
			    "source": "1-day"
			} ] } ]
	    }
	};				
	schedulesLoaded.push({ "schedule": nterm,
			       "numModifications": 0,
			       "modTime": nterm.modificationTime,
			       "previous": "", "displayedProject": 0 });
	displayedSchedule = schedulesLoaded.length - 1;
	// We also have to put a new entry in the term select for this.
	if (createdSemesters.hasOwnProperty(nterm.program.observatory.observatory)) {
	    createdSemesters[nterm.program.observatory.observatory].push(termName);
	} else {
	    createdSemesters[nterm.program.observatory.observatory] = [ termName ];
	}
	addSemesters(nterm.program.observatory.observatory, termName);
	fillScheduleElements();
	fillProjectElements();
    }
};

const saveScheduleToServer = function() {
    var scheduleLoaded = schedulesLoaded[displayedSchedule];
    if (scheduleLoaded.numModifications <= 0) {
	console.log("no need to save unmodified schedule");
	return;
    }
    var scheduleData = scheduleLoaded.schedule;
    if ((scheduleData != null) && (authenticated == 1)) {
	var xhr = new XMLHttpRequest();
	xhr.open("POST", spath, true)
	xhr.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
	xhr.responseType = "json";
	xhr.onload = function() {
	    var status = xhr.status;
	    if (status === 200) {
		console.log("Schedule saved to the server.");
		var resp = JSON.parse(xhr.response.received);
		scheduleLoaded.modTime = resp.modificationTime;
		scheduleLoaded.schedule.modificationTime = resp.modificationTime;
		scheduleLoaded.numModifications = 0;
		scheduleLoaded.previous = "";
		fillScheduleElements();
		fillProjectElements();
	    } else {
		console.log("Failed to save schedule to the server.");
	    }
	}
	var sstring = "request=save&observatory=" +
	    scheduleData.program.observatory.observatory +
	    "&term=" + scheduleData.program.term.term +
	    "&schedule=" + JSON.stringify(scheduleData);
	xhr.send(sstring);
    }
};

// Add a click handler for a DOM element.
const addClickHandler = function(e, callback) {
  if (e) {
    e.addEventListener("click", callback);
    // Add the class to show it can be clicked.
    domAddClasses(e, "clickEnabled");
  }
};

// Clear the error class if an input is modified.
const removeErrorHandler = function(e) {
    if (e && e.target) {
	domRemoveClasses(e.target, "inputError");
    }
};

getAuthenticated(getObservatoryList);
document.getElementById("observatory").addEventListener("change", fillObservatoryDetails);
addClickHandler(document.getElementById("observatoryModifyButton"), modifyObservatoryHandler);
document.getElementById("termObservatory").addEventListener("change", getSemesterList);
document.getElementById("termSelect").addEventListener("change", loadFile);
document.getElementById("projectSelect").addEventListener("change", fillProjectElements);
document.getElementById("slotModifySelect").addEventListener("change", slotSelectionHandler);
addClickHandler(document.getElementById("modifySlotButton"), slotModifier);
addClickHandler(document.getElementById("deleteSlotsButton"), slotDeleter);
addClickHandler(document.getElementById("addSlotButton"), slotAdder);
document.getElementById("addSlotSourceName").addEventListener("change", removeErrorHandler);
document.getElementById("addSlotRA").addEventListener("change", removeErrorHandler);
document.getElementById("addSlotDec").addEventListener("change", removeErrorHandler);
document.getElementById("addSlotNumSlots").addEventListener("change", removeErrorHandler);
document.getElementById("addSlotConfig").addEventListener("change", removeErrorHandler);
document.getElementById("projectCode").addEventListener("change", removeErrorHandler);
document.getElementById("projectScore").addEventListener("change", removeErrorHandler);
document.getElementById("projectPISurname").addEventListener("change", removeErrorHandler);
document.getElementById("projectPIEmail").addEventListener("change", removeErrorHandler);
document.getElementById("projectTitle").addEventListener("change", removeErrorHandler);
document.getElementById("termName").addEventListener("change", removeErrorHandler);
document.getElementById("termStartDate").addEventListener("change", removeErrorHandler);
document.getElementById("termEndDate").addEventListener("change", removeErrorHandler);
document.getElementById("termFirstConfig").addEventListener("change", removeErrorHandler);
document.getElementById("termConfigOwner").addEventListener("change", removeErrorHandler);
document.getElementById("observatoryName").addEventListener("change", removeErrorHandler);
document.getElementById("observatoryShortName").addEventListener("change", removeErrorHandler);
document.getElementById("observatoryFullName").addEventListener("change", removeErrorHandler);
document.getElementById("observatoryLongitude").addEventListener("change", removeErrorHandler);
document.getElementById("observatoryLatitude").addEventListener("change", removeErrorHandler);
document.getElementById("observatoryTimezoneHours").addEventListener("change", removeErrorHandler);
document.getElementById("observatoryTimezone").addEventListener("change", removeErrorHandler);
document.getElementById("observatoryElevationLimit").addEventListener("change", removeErrorHandler);
document.getElementById("projectType").addEventListener("change", projectTypeChanged);
document.getElementById("projectColourStandard").addEventListener("change", colourSelectChanged);
document.getElementById("projectColour").addEventListener("change", colourBoxChanged);
addClickHandler(document.getElementById("projectModifyButton"), projectModifier);
addClickHandler(document.getElementById("scheduleUndoModification"), undoScheduleModification);
addClickHandler(document.getElementById("termModifyButton"), termModifier);
addClickHandler(document.getElementById("projectDeleteButton"), projectDeleter);
addClickHandler(document.getElementById("scheduleServerSave"), saveScheduleToServer);
