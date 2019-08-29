/**
 * HTML scheduler for ATCA and Parkes.
 * Jamie Stevens 2019
 */

/********************************************************************
 * GLOBAL VARIABLES
 * We use these in various ways throughout the code.
 */
var arrayLayer = null;
var arrayGroup = null;
var scheduleData = null;
var scheduleFirst = null;
var scheduleLast = null;
var serverModificationTime = null;
var localModificationTime = null;
var localChecked = false;
var semesterStart = null;
var semesterEnd = null;
var allProjectSummary = null;
var constraintLayer = null;
var constraintBoxGroup = null;
var backgroundLayer = null;
var blockLayer = null;
var allDates = null;
var stage = null;
var previouslySelectedProject = null;
var previouslySelectedSlot = null;
var obs = null;
var semester = null;
// This contains all the nodes for each project in the table.
var tableRows = {};
// This contains all the block Konva objects.
var blockObjects = [];
// We need two transformers.
var transformerTop = null;
var transformerBottom = null;

// Some constants we need.
// The observatory coordinates.
const coordinates = {
  'atca': { 'longitude': 149.5501388, 'latitude': -30.3128846 },
  'parkes': { 'longitude': 148.2635101, 'latitude': -32.9984064 }
};
const elLimit = { 'atca': 12, 'parkes': 30 };
// The number of days to display (basically half a leap year, plus a few.
const nDays = (366 / 2) + 7;
// Time limits for certain projects.
const legacyProjects = [ "C3132", "C3145", "C3152", "C3157" ];
const legacyLimit = 400; // Hours.
const projectLimit = 300; // Hours
// The colour of the border to use for the blocks, when not highlighted.
const normalBlockColour = "black";
// And the stroke width.
const normalBlockStroke = 2;
// The same things, for highlighted blocks.
const highlightedBlockColour = "brown";
const highlightedBlockStroke = 4;
const localKey = "atnfSchedule";
const observatoryKey = "atnfObservatory";
const semesterKey = "atnfSemester";
const spath = "/cgi-bin/scheduler.pl";
const obsNames = { 'atca': "ATCA", 'parkes': "Parkes" };

// An object to describe config compatibility.
// The keys are the available configs, which we can use later to
// allow for config selection. Each value is an array with the names
// of all config requirements that are compatible.
const configDescriptor = { 'atca': {
  '6a': [ 0, "any", "any6", "any 750 or greater", "6a" ],
  '6b': [ 1, "any", "any6", "any 750 or greater", "6b" ],
  '6c': [ 2, "any", "any6", "any 750 or greater", "6c" ],
  '6d': [ 3, "any", "any6", "any 750 or greater", "6d" ],
  '1.5a': [ 4, "any", "any1.5", "any 750 or greater", "1.5a" ],
  '1.5b': [ 5, "any", "any1.5", "any 750 or greater", "1.5b" ],
  '1.5c': [ 6, "any", "any1.5", "any 750 or greater", "1.5c" ],
  '1.5d': [ 7, "any", "any1.5", "any 750 or greater", "1.5d" ],
  '750a': [ 8, "any", "any750", "any 750 or greater", "750a" ],
  '750b': [ 9, "any", "any750", "any 750 or greater", "750b" ],
  '750c': [ 10, "any", "any750", "any 750 or greater", "750c" ],
  '750d': [ 11, "any", "any750", "any 750 or greater", "750d" ],
  'ew367': [ 12, "any", "anycompact", "ew367" ],
  'ew352': [ 13, "any", "anycompact", "ew352" ],
  'h214': [ 14, "any", "hybrid", "h214" ],
  'h168': [ 15, "any", "hybrid", "h168", "h75/168" ],
  'h75': [ 16, "any", "hybrid", "h75", "h75/168" ]
}, 'parkes': {
  'uwl': [ 0, "any", "uwl" ],
  'mb': [ 1, "any", "multi", "mb" ],
  'mars': [ 2, "any", "mars" ],
  'k': [ 3, "any", "13mm", "k" ],
  'ku': [ 4, "any", "ku" ],
  '10/50': [ 5, "any", '10/50' ],
  'vlbi': [ 6, "any" ]
} };

// An object to hold all our measurements.
var meas = {
  // The width of a half-hour (the smallest increment we schedule to).
  halfHourWidth: 12,
  // The margin around the schedule box.
  marginLeft: 20,
  //marginTop: 60,
  marginTop: 2,
  // The width of the right-side area where we see the individual elements.
  elementWidth: 0,
  // The height of a single day.
  dayHeight: 40,
  // The width of the label which holds the date string.
  dayLabelWidth: 140,  
  // The width of the array panel.
  arrayLabelWidth: 80,
  // The height of the hour label part.
  timeLabelHeight: 66,
  // The offset of all text from the edges.
  textOffset: 2,
  // Font size for the support text.
  supportFontSize: 9
};


// Compute some secondary measurements from the primary measurements.
// The width of an entire day.
meas.dayWidth = 48 * meas.halfHourWidth;
// The canvas width.
meas.width = meas.dayWidth + 3 * meas.marginLeft + meas.elementWidth + meas.dayLabelWidth + meas.arrayLabelWidth;
// The canvas height.
meas.height = nDays * meas.dayHeight + 2 * meas.marginTop;









/********************************************************************
 * HELPER FUNCTIONS
 * These following functions don't do anything to the page, but
 * can be used by any other function for useful purposes.
 */

const calcDayNumber = function(d) {
  if (d instanceof Date) {
    return (Math.floor((d.getTime() - scheduleFirst.getTime()) / (86400 * 1000)) + 1);
  } else {
    return (Math.floor((d - (scheduleFirst.getTime() / 1000)) / 86400) + 1);
  }
};

// This routine calculates the sidereal restrictions for a particular
// source on a particular day.
const calculateSiderealRestrictions = function(raStr, decStr, d) {
  var ra = stringToDegrees(raStr, true);
  var dec = stringToDegrees(decStr, false);
  var sourceRiseSets = calculateSourceStuff([ ra, dec ], d,
					   elLimit[obs]);
  return sourceRiseSets;
};

// Given some coordinates c (an array with RA, Dec in degrees),
// on a Date d, calculate the rise hour and set hour in the day.
// Use the elevation limit ellimit.
const calculateSourceStuff = function(c, d, ellimit) {
  var mjd = date2mjd(d);
  var haset = haset_azel(c[1], coordinates[obs].latitude, ellimit);
  var riseHour = (c[0] - haset) / 15;
  var setHour = (c[0] + haset) / 15;
  var r = lstToDaytime(riseHour, setHour, (c[0] / 15), d);
  if (haset == 180) {
    r.alwaysUp = true;
  }
  return r;
};

const calculateSunStuff = function(d) {
  var mjd = date2mjd(d);
  var sp = sunPosition(mjd);
  return calculateSourceStuff(sp.map(rad2deg), d, 0);
};

// Remove any blocks in the block object that require cleaning.
const cleanBlockObjects = function() {
  var boidx = -1;
  do {
    boidx = -1;
    for (var i = 0; i < blockObjects.length; i++) {
      if (blockObjects[i].clean) {
	boidx = i;
	break;
      }
    }
    
    if (boidx >= 0) {
      if (blockObjects[boidx].group != null) {
	blockObjects[boidx].group.destroy();
      }
      blockObjects.splice(boidx, 1);
    }
  } while (boidx >= 0);
};

// This function compares two dates simply looking if the date and
// month are the same.
const compareDates = function(d1, d2) {
  if (d1 == d2) {
    return 0;
  } else if ((d1.getDate() == d2.getDate()) &&
      (d1.getMonth() == d2.getMonth())) {
    // Identical.
    return 0;
  } else if (d1.getTime() < d2.getTime()) {
    return -1;
  } else {
    return 1;
  }
};

// Compare two arrays which just have strings as elements.
// We don't care if the order is different, just if the
// same strings appear in each.
const compareStringArrays = function(a, b) {
  // Check length.
  if (a.length != b.length) {
    return false;
  }

  for (var i = 0; i < a.length; i++) {
    if (b.indexOf(a[i]) < 0) {
      return false;
    }
  }

  return true;
};

const convertSmallDates = function(smdates) {
  // Split the date string.
  var sms = smdates.split(",");
  var darr = sms.map(smallStringToDatetime);
  var rarr = darr.map(function(d) {
    return (d.getTime() / 1000);
  });

  return rarr;
};

// Calculate the Julian day for a midnight AEST on a given Date d.
var date2mjd = function(d) {
  // We assume that we are at midnight AEST, which is 14 in UTC.
  var utc = d.getUTCDate() + (14 / 24);
  var mm = d.getUTCMonth() + 1;
  var m = mm;
  var y = d.getUTCFullYear();
  if (mm <= 2) {
    m = mm + 12;
    y = d.getUTCFullYear() - 1;
  }
  var A = Math.floor(y / 100);
  var B = 2 - A + Math.floor(A / 4);

  var C = Math.floor(365.25 * y);
  var D = Math.floor(30.6001 * (m + 1));
  var mjd = B + C + D + utc + 1720994.5 - 2400000.5;
  return mjd;
};

const datetimeToSmallString = function(dts) {
  var dt = new Date(dts * 1000);
  return (dt.getDate() + "/" + (dt.getMonth() + 1));
};

const datetimeToString = function(d) {
  return d.getFullYear() + "-" +
    zeroPadNumber((d.getMonth() + 1), 10) + "-" +
    zeroPadNumber(d.getDate(), 10) + " " +
    zeroPadNumber(d.getHours(), 10) + ":" +
    zeroPadNumber(d.getMinutes(), 10) + ":" +
    zeroPadNumber(d.getSeconds(), 10);
};

// Convert degrees to radians.
const deg2rad = function(d) {
  return (d * Math.PI / 180);
};

const degreesBounds = function(d) {
  return numberBounds(d, 360);
};

// Function to calculate the DOY.
const doy = function(d) {
  var foy = new Date(d.getFullYear(), 0, 1, 0, 0, 0, 0);
  var td = Math.floor((d.getTime() - foy.getTime()) / (86400 * 1000));
  return (td + 1);
};

// Function to compensate for Eastern Standard Time.
// This isn't necessary any more now that I got the time stuff
// figured out properly, but it has its use still.
const easternStandardTime = function(jsEpoch) {
  if (jsEpoch instanceof Date) {
    return (jsEpoch.getTime() / 1000);
  } else {
    return (jsEpoch / 1000);
  }
};

// Find a block in the block object.
const findBlockObject = function(proj, slot) {
  for (var i = 0; i < blockObjects.length; i++) {
    if ((blockObjects[i].ident == proj.ident) &&
	(blockObjects[i].slot == slot) &&
	(!blockObjects[i].moving) && (!blockObjects[i].clean)) {
      return blockObjects[i];
    }
  }

  return null;
};

// Calculate the sidereal time at Greenwich, given an MJD.
const gst = function(mjd, dUT1) {
  var a = 101.0 + 24110.54581 / 86400.0;
  var b = 8640184.812886 / 86400.0;
  var e = 0.093104 / 86400.0;
  var d = 0.0000062 / 86400.0;
  var tu = (mjd - (2451545.0 - 2400000.5)) / 36525.0;
  var sidtim = turnFraction(a + tu * (b + tu * (e - tu * d)));
  var gmst = turnFraction(sidtim + (mjd - Math.floor(mjd) + dUT1 / 86400.0) *
			  1.002737909350795);
  return gmst;
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

const hourBounds = function(h) {
  return numberBounds(h, 24);
};

// Given some sidereal time at time 0, work out how many real hours
// until some nominated sidereal time.
const hoursUntilLst = function(zlst, dlst) {
  if (dlst < zlst) {
    dlst += 24;
  }

  return ((dlst - zlst) / 1.002737909350795);
};

// Work out the hours for a given LST rise and set.
const lstToDaytime = function(lstRise, lstSet, ra, d) {
  var mjd = date2mjd(d);
  var riseHour = hourBounds(lstRise);
  var setHour = hourBounds(lstSet);
  var midHour;
  if (ra == null) {
    midHour = hourBounds((lstRise + (lstSet - lstRise) / 2));
  } else {
    midHour = ra;
  }
  var zlst = 24 * mjd2lst(mjd, (coordinates[obs].longitude / 360.0), 0);
  var riseDayHour = hoursUntilLst(zlst, riseHour);
  var setDayHour = hoursUntilLst(zlst, setHour);
  var midDayHour = hoursUntilLst(zlst, midHour);
  return { rise: riseDayHour, set: setDayHour, zenith: midDayHour };
};

// Calculate the sidereal time at some longitude on the Earth.
const mjd2lst = function(mjd, longitude, dUT1) {
  var lst = turnFraction(gst(mjd, dUT1) + longitude);
  return lst;
};

// Given any number n, put it between 0 and some other number b.
const numberBounds = function(n, b) {
  while (n > b) {
    n -= b;
  }
  while (n < 0) {
    n += b;
  }
  return n;
};

// Function to take a JS Date and output the string that would
// go in the left date box.
const printDate = function(d) {
  var m = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun",
	    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ];
  var w = [ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" ];
  var yd = doy(d);
  var yds = "" + yd;
  if (yd < 100) {
    if (yd >= 10) {
      yds = "0" + yd;
    } else {
      yds = "00" + yd;
    }
  }
  var r = w[d.getDay()] + " " + m[d.getMonth()] + " " + d.getDate() +
      " (" + yds + ")";
  return r;
};

// Convert radians to degrees.
const rad2deg = function(r) {
  return (r * 180 / Math.PI);
};

// Remove a block in the block object.
const removeBlockObject = function(proj, slot) {
  var boidx = -1;
  for (var i = 0; i < blockObjects.length; i++) {
    if ((blockObjects[i].ident == proj.ident) &&
	(blockObjects[i].slot == slot)) {
      boidx = i;
      break;
    }
  }

  if (boidx >= 0) {
    blockObjects.splice(boidx, 1);
  }
};

// We take a date/month string and work out the date given
// our semester constraint.
const smallStringToDatetime = function(smstr) {
  var dels = smstr.split("/");
  var year = semesterStart.getFullYear();
  var checkDate = new Date(year, parseInt(dels[1] - 1), parseInt(dels[0]));
  if (checkDate.getTime() < semesterStart.getTime()) {
    // We're probably in the next year.
    checkDate = new Date(year + 1, dels[1] - 1, dels[0]);
  } else if (checkDate.getTime() > semesterEnd.getTime()) {
    // There should be no way this happens.
    console.log("found a too big date, weirdly");
    return null;
  }

  // We should now be in range.
  if ((checkDate.getTime() >= semesterStart.getTime()) &&
      (checkDate.getTime() < semesterEnd.getTime())) {
    return checkDate;
  } else {
    // Poop.
    console.log("Unable to fit the date!");
    return null;
  }
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

// Work out where the Sun is on a particular date.
const sunPosition = function(mjd) {
  // Calculate the number of days since 0 UTC Jan 1 2000.
  var jd = mjd + 2400000.5;
  var n = jd - 2451545.0;
  // The longitude of the Sun, in degrees.
  var L = 280.46 + 0.9856474 * n;
  // Mean anomaly of the Sun, in degrees.
  var g = 357.528 + 0.9856003 * n;
  // Ensure bound limits for these numbers.
  L = degreesBounds(L);
  g = degreesBounds(g);
  // Ecliptic longitude of the Sun, in degrees.
  var lambda = L + 1.915 * Math.sin(deg2rad(g)) + 0.020 *
      Math.sin(2 * deg2rad(g));
  // Sun distance from Earth.
  var R = 1.00014 - 0.01671 * Math.cos(deg2rad(g)) -
      0.00014 * Math.cos(2 * deg2rad(g));
  // The obliquity, in degrees.
  // We need the number of centuries since J2000.0.
  var T = (n / (100.0 * 365.2525));
  var epsilon = 23.4392911 - (46.636769 / 3600.0) * T -
      (0.0001831 / 3600.0) * T * T +
      (0.00200340 / 3600.0) * T * T * T;
  // Get the right ascension in radians.
  var alpha = Math.atan2(Math.cos(deg2rad(epsilon)) * Math.sin(deg2rad(lambda)),
			 Math.cos(deg2rad(lambda)));
  // And declination, in radians.
  var delta = Math.asin(Math.sin(deg2rad(epsilon)) * Math.sin(deg2rad(lambda)));
  return [ alpha, delta ];
};

// Given any number, put it between 0 and 1.
const turnFraction = function(f) {
  return numberBounds(f, 1);
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





/********************************************************************
 * DOM FUNCTIONS
 * These functions manipulate the DOM.
 */

// Add one or more classes to a DOM element.
const domAddClasses = function(e, addClasses) {
  if ((typeof e == "undefined") || (e == "undefined")) {
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
  if ((typeof e == "undefined") || (e == "undefined")) {
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

// A little helper function to do things to a DOM element.
const fillId = function(id, text, addClasses, remClasses) {
  // Try to find the ID.
  var e = document.getElementById(id);
  if ((typeof e == "undefined") || (e == "undefined")) {
    console.log("cannot find DOM element with id " + id);
    return;
  }

  if ((typeof text != "undefined") && (text != null) &&
      (typeof e != "undefined") && (e != null)) {
    e.innerHTML = text;
  }

  domAddClasses(e, addClasses);
  domRemoveClasses(e, remClasses);
  
  
};

// A little helper function to fill input values.
const fillInput = function(id, text) {
  var e = document.getElementById(id);
  if ((typeof e == "undefined") || (e == "undefined")) {
    console.log("cannot find input with id " + id);
    return;
  }

  if ((typeof text != "undefined") && (text != null)) {
    e.value = text;
  }
};

// Determine the selected observatory.
const getObservatory = function() {
  var oe = document.getElementById("observatory");
  var cobs = oe.options[oe.selectedIndex].value;
  var sobs = window.localStorage.getItem(observatoryKey);
  if (obs == null) {
    // We've likely just been loaded.
    console.log("loading page now");
    if ((sobs == null) || (sobs == "null")) {
      // Use the page observatory, because no cache value has been found.
      console.log("setting observatory to " + cobs);
      obs = cobs;
    } else {
      // Use the one the user used previously.
      obs = sobs;
    }
  } else {
    // Has this been changed?
    if (cobs != obs) {
      // The user wants a different observatory.
      obs = cobs;
      localChecked = false;
      localModificationTime = null;
      serverModificationTime = null;
      checkServerTime(pageInitBootstrap);
      checkLocalTime(pageInitBootstrap);
    }
  }
  // Store this value.
  window.localStorage.setItem(observatoryKey, obs);

  // Display the correct slot selection header.
  var ah = document.getElementById("atcaSlotSelectionHeader");
  console.log("selection headers follow");
  var ph = document.getElementById("parkesSlotSelectionHeader");
  if (obs == "atca") {
    domAddClasses(ph, "invisible");
    domRemoveClasses(ah, "invisible");
  } else if (obs == "parkes") {
    domAddClasses(ah, "invisible");
    domRemoveClasses(ph, "invisible");
  }
};

// Determine the semester to show.
const getSemester = function() {
  var ts = document.getElementById("termSelected");
  var csem = null;
  console.log(ts.options);
  console.log(ts.selectedIndex);
  if (ts.selectedIndex != -1) {
    csem = ts.options[ts.selectedIndex].value;
  }
  var ssem = window.localStorage.getItem(semesterKey);
  var n = new Date();
  if (semester == null) {
    // We've likely just been loaded.
    // Check if the saved semester is valid.
    console.log(ssem);
    if ((typeof ssem != "undefined") && (ssem != "undefined") &&
	(ssem != null)) {
      // Something has been cached, so we check if the cache has
      // expired.
      var jssem = JSON.parse(ssem);
      var o = new Date(jssem.time);
      if ((n.getTime() - o.getTime()) < (5 * 86400 * 1000)) {
	// This was set less than 5 days ago, so this is valid.
	semester = jssem.semester;
      }
    }
  } else {
    // Has the semester been changed.
    if (csem != semester) {
      // The user wants a different term.
      semester = csem;
      localChecked = false;
      localModificationTime = null;
      serverModificationTime = null;
      checkServerTime(pageInitBootstrap);
      checkLocalTime(pageInitBootstrap);
    }
  }

  // Store this value.
  if (semester != null) {
    window.localStorage.setItem(semesterKey, JSON.stringify({
      'time': n.getTime(), 'semester': semester
    }));
  }
};

const isElementVisible = function(el) {
    var rect     = el.getBoundingClientRect(),
        vWidth   = window.innerWidth || doc.documentElement.clientWidth,
        vHeight  = window.innerHeight || doc.documentElement.clientHeight,
        efp      = function (x, y) { return document.elementFromPoint(x, y) };     

    // Return false if it's not in the viewport
    if (rect.right < 0 || rect.bottom < 0 
            || rect.left > vWidth || rect.top > vHeight)
        return false;

    // Return true if any of its four corners are visible
    return (
          el.contains(efp(rect.left,  rect.top))
      ||  el.contains(efp(rect.right, rect.top))
      ||  el.contains(efp(rect.right, rect.bottom))
      ||  el.contains(efp(rect.left,  rect.bottom))
    );
};

// A helper function to make a DOM element.
const makeElement = function(type, text, attrs, classes) {
  var e = document.createElement(type);
  if ((typeof text != "undefined") && (text != null)) {
    e.innerHTML = text;
  }
  if ((typeof attrs != "undefined") && (attrs != null)) {
    for (var a in attrs) {
      if (attrs.hasOwnProperty(a)) {
	var n = document.createAttribute(a);
	n.value = attrs[a];
	e.setAttributeNode(n);
      }
    }
  }

  if ((typeof classes != "undefined") && (classes != null)) {
    domAddClasses(e, classes);
  }
  
  return e;
};

// Add a message to the message window.
const printMessage = function(msg, type) {
  if (typeof msg == "undefined") {
    return;
  }
  if (typeof type == "undefined") {
    type = "normal";
  }

  var classes = [ ];
  if (type == "error") {
    classes.push("messageError");
  } else if (type == "warning") {
    classes.push("messageWarning");
  }
  // Get the date stamp.
  var d = new Date();
  var dstring = datetimeToString(d) + ":";
  
  var mel = makeElement("div")
  var dbox = makeElement("span", dstring, null, "messageDate");
  mel.appendChild(dbox);
  var mbox = makeElement("span", msg, null, classes);
  mel.appendChild(mbox);
  var mb = document.getElementById("messagebox");
  mb.appendChild(mel);
  // Scroll to the bottom.
  mb.scrollTop = mb.scrollHeight;
};

// Scroll to a timestamp in the schedule canvas.
// The timestamp is just the epoch (the scheduled_start).
const scrollToTimestamp = function(t) {
  var dn = calcDayNumber(t);
  // Check if this is already visible.
  var e = document.getElementById("schedtable");
  var topDay = Math.ceil((e.scrollTop - meas.marginTop) / meas.dayHeight);
  var bottomDay = Math.floor(topDay + e.clientHeight / meas.dayHeight);

  if ((dn >= topDay) && (dn <= bottomDay)) {
    // Don't need to do anything, it's already visibile.
    return;
  }

  // Scroll to leave a few days at the top.
  if (dn > 4) {
    dn -= 4;
  } else {
    dn = 0;
  }
  // Work out the position of that day.
  var dt = meas.marginTop + dn * meas.dayHeight;
  e.scrollTop = dt;
};

// Set the observatory.
const setObservatory = function(sobs) {
  var oe = document.getElementById("observatory");
  window.localStorage.setItem(observatoryKey, sobs);
  for (var i = 0; i < oe.options.length; i++) {
    if (oe.options[i].value == sobs) {
      oe.options[i].setAttribute("selected", "selected");
    } else {
      oe.options[i].removeAttribute("selected");
    }
  }

};

// Set the semester.
const setSemester = function(ssem) {
  var n = new Date();
  var ts = document.getElementById("termSelected");
  window.localStorage.setItem(semesterKey, JSON.stringify({
    'time': n.getTime(), 'semester': ssem
  }));
  // Go to the server and ask for the list of possible semesters.
  var xhr = new XMLHttpRequest();
  xhr.open('GET', spath + "?request=listsemesters&" +
	   "observatory=" + obs, true);
  xhr.responseType = "json";
  xhr.onload = function() {
    var status = xhr.status;
    if (status == 200) {
      emptyDomNode("termSelected");
      var asem = xhr.response.semesters;
      asem.sort();
      asem.reverse();
      for (var i = 0; i < asem.length; i++) {
	var o = document.createElement("option");
	o.setAttribute("value", asem[i]);
	o.innerHTML = asem[i];
	if (asem[i] == ssem) {
	  o.setAttribute("selected", "selected");
	}
	ts.appendChild(o);
      }
    } else {
      console.log("failure while getting list of semesters");
    }
  };
  xhr.send();
  
};

// Show the details of a particular project, and present the slot
// scheduling interface for it.
const showProjectDetails = function(ident) {
  // Find the project by its ident.
  var project = getProjectByName(ident);

  if (project.details == null) {
    console.log("something has gone horribly wrong");
    return;
  }

  // Deselect any previously selected project, unless it's us.
  var tableRedrawRequired = true;
  if ((previouslySelectedProject != null) &&
      (previouslySelectedProject.details.ident != ident)) {
    fillId("row-" + previouslySelectedProject.details.ident, null,
	   null, "selectedProject");
    // And dehighlight any selected slot on the canvas.
    if ((previouslySelectedSlot != null) &&
	(previouslySelectedProject.details.slot[previouslySelectedSlot]
	 .scheduled == 1)) {
      dehighlightBlock(previouslySelectedProject.details,
		       previouslySelectedSlot);
    }
    previouslySelectedProject = null;
    previouslySelectedSlot = null;
  } else if ((previouslySelectedProject != null) &&
	     (previouslySelectedProject.details.ident == ident)) {
    // We've already been selected, we just need to update the
    // table when we come to it.
    tableRedrawRequired = false;
  }

  var makeRow = function(sn, sd, tab) {
    var rid = "slotrow-" + ident + "-" + sn;
    var tr = makeElement("tr", null, {
      'id': rid
    });
    tab.appendChild(tr);
    if (sd.scheduled_duration >= sd.requested_duration) {
      fillId(rid, null, "completelyScheduled");
    } else if (sd.scheduled_duration > 0) {
      fillId(rid, null, "partiallyScheduled");
    }
    var tsel = makeElement("th", "&nbsp;", {
      'id': "slotselected-" + ident + "-" + sn
    });
    tr.appendChild(tsel);
    var arrId = "slotarray-" + ident + "-" + sn;
    var td = null;
    if (obs == "atca") {
      td = makeElement("td", sd.array.toUpperCase(), {
	'id': arrId
      });
    } else if (obs == "parkes") {
      var arrString = "";
      if (sd.array instanceof Array) {
	arrString = sd.array.join(",").toUpperCase();
      } else {
	arrString = sd.array.toUpperCase();
      }
      td = makeElement("td", arrString, {
	'id': arrId
      });
    }
    // Add a double-click handler on the array.
    addDoubleClickHandler(td,
			  arraySelectorGen(ident, sn, arrId));
    tr.appendChild(td);
    if (obs == "atca") {
      var bandId = "slotband-" + ident + "-" + sn;
      td = makeElement("td", sd.bands.join(","), { 'id': bandId });
      addDoubleClickHandler(td,
			    bandsSelectorGen(ident, sn, bandId));
      tr.appendChild(td);
    }
    var bandwidthId = "slotbandwidth-" + ident + "-" + sn;
    td = makeElement("td", sd.bandwidth, { 'id': bandwidthId });
    if (obs == "atca") {
      addDoubleClickHandler(td, cabbSelectorGen(ident, sn,
						bandwidthId));
    } else if (obs == "parkes") {
      addDoubleClickHandler(td, backendSelectorGen(ident, sn, bandwidthId));
    }
    tr.appendChild(td);
    var sourceId = "slotsource-" + ident + "-" + sn;
    td = makeElement("td", sd.source, { 'id': sourceId });
    addDoubleClickHandler(td, sourceSelectorGen(ident, sn, sourceId));
    tr.appendChild(td);
    var timeId = "slottime-" + ident + "-" + sn;
    td = makeElement("td", sd.scheduled_duration + " / " +
		     sd.requested_duration, { 'id': timeId });
    addDoubleClickHandler(td,
			  timeSelectorGen(ident, i, timeId));
    tr.appendChild(td);
      
    // Add a click handler on this row.
    addClickHandler(tr, slotSelectorGen(sn));
  };

  var slotTable = emptyDomNode("projectslotsSelectionBody");
  
  if (tableRedrawRequired) {
    // Select the row in the table.
    previouslySelectedProject = project;
    var projrowId = "row-" + project.details.ident;
    fillId(projrowId, null, "selectedProject");
    var projrow = document.getElementById(projrowId);
    if (!isElementVisible(projrow)) {
      projrow.scrollIntoView();
    }
    
    // Display the vital statistics.
    //console.log(project);
    fillId("projectselectedIdent", project.details.ident);
    fillId("projectselectedPI", project.details.PI);
    fillId("projectselectedTitle", project.details.title);
    var projectselectedTable = document.getElementById("projectselected");
    projectselectedTable.style["background-color"] = "#" + project.summary.colour;
    
    // Display the comments for the project.
    fillId("projectcomments", project.details.comments);
    // Show the date preferences.
    var nc = document.getElementById("nighttime");
    if (project.details.prefers_night == 0) {
      nc.checked = false;
    } else {
      nc.checked = true;
    }
    if ((project.details.excluded_dates instanceof Array) &&
	(project.details.excluded_dates.length > 0)) {
      project.details.excluded_dates.sort();
      var datestrings = project.details.excluded_dates.map(datetimeToSmallString);
      fillInput("baddates", datestrings.join(","));
    } else {
      // Blank the input.
      fillInput("baddates", "");
    }
    if ((project.details.preferred_dates instanceof Array) &&
	(project.details.preferred_dates.length > 0)) {
      project.details.preferred_dates.sort();
      var datestrings = project.details.preferred_dates.map(datetimeToSmallString);
      fillInput("gooddates", datestrings.join(","));
    } else {
      fillInput("gooddates", "");
    }

    // Blank out the RA/Dec/LST inputs.
    fillInput("sourceRightAscension", "");
    fillInput("sourceDeclination", "");
    fillInput("sourceLSTRise", "");
    fillInput("sourceLSTSet", "");
    var ul = document.getElementById("sourceUseLST");
    ul.checked = false;
    // Get rid of any restrictions plotted.
    constraintBoxGroup.destroyChildren();
    constraintLayer.draw();
    
    // Make a table with each of the slots.
    // Empty the current table.
    for (var i = 0; i < project.details.slot.length; i++) {
      var s = project.details.slot[i];
      makeRow(i, s, slotTable);
    }
  } else {
    // Update the cell values only. We do this for everything in case
    // we've been called because an input/select has been changed.
    //console.log("updating table only");
    for (var i = 0; i < project.details.slot.length; i++) {
      var s = project.details.slot[i];
      // Check the row exists, or make it if not.
      var r = document.getElementById("slotrow-" + ident + "-" + i);
      if (!r) {
	makeRow(i, s, slotTable);
      }
      // Go through each ID in turn.
      var arrId = "slotarray-" + ident + "-" + i;
      emptyDomNode(arrId);
      var arrString = "";
      if (s.array instanceof Array) {
	arrString = s.array.join(",").toUpperCase();
      } else {
	arrString = s.array.toUpperCase();
      }
      fillId(arrId, arrString);

      if (obs == "atca") {
	var bandId = "slotband-" + ident + "-" + i;
	emptyDomNode(bandId);
	fillId(bandId, s.bands.join(","));
      }

      var bandwidthId = "slotbandwidth-" + ident + "-" + i;
      emptyDomNode(bandwidthId);
      fillId(bandwidthId, s.bandwidth);

      var sourceId = "slotsource-" + ident + "-" + i;
      emptyDomNode(sourceId);
      fillId(sourceId, s.source);
      
      var timeId = "slottime-" + ident + "-" + i;
      emptyDomNode(timeId);
      fillId(timeId, s.scheduled_duration + " / " +
	     s.requested_duration);

      // Ensure we colour our selection if we are.
      var tselId = "slotrow-" + ident + "-" + i;
      if (i == previouslySelectedSlot) {
	fillId(tselId, null, "slotSelected");
      }

      if (s.scheduled_duration >= s.requested_duration) {
	fillId(tselId, null, "completelyScheduled", "partiallyScheduled");
      } else if (s.scheduled_duration > 0) {
	fillId(tselId, null, "partiallyScheduled", "completelyScheduled");
      } else {
	fillId(tselId, null, null,
	       [ "partiallyScheduled", "completelyScheduled" ]);
      }

    }
  }
  
};

// Update all the numbers and styling in all the tables.
const updateAllTables = function() {
  updateSemesterSummary();
  updateProjectTable();
  showProjectDetails(previouslySelectedProject.details.ident);
};





/********************************************************************
 * CANVAS FUNCTIONS
 * These functions draw onto the scheduling canvas.
 */

// Dehighlight a selected schedule block.
const dehighlightBlock = function(proj, slot) {
  var bo = findBlockObject(proj, slot);
  for (var i = 0; i < bo.rects.length; i++) {
    bo.rects[i].stroke(normalBlockColour);
    bo.rects[i].strokeWidth(normalBlockStroke);
  }
  // Make it impossible to drag this block.
  bo.group.draggable(false);
  // And detach our transformers.
  transformerTop.detach()
  transformerBottom.detach();
  blockLayer.draw();
};

const dragConstructor = function(block) {
  return function(pos) {
    dragFinished(block, pos);
  };
};

// Function that gets called when a block drag has finished.
const dragFinished = function(block, pos) {
  var xn = block.rectOpts[0].x + pos.currentTarget.attrs.x;
  var yn = block.rectOpts[0].y + pos.currentTarget.attrs.y +
      (block.rectOpts[0].height / 2);
  var timen = posTime(xn, yn);
  // Set the current block to moving so we don't consider it
  // during the move.
  block.moving = true;
  var scheduled = scheduleInsert(block.ident, block.slot,
				 timen, true);
  if (scheduled != null) {
    var origTimePos = posTime(block.rectOpts[0].x, block.rectOpts[0].y);
    var origDate = new Date(origTimePos.timestamp * 1000);
    var newDate = new Date(scheduled.scheduled_start * 1000);
    printMessage(block.ident + " slot moved from " +
		 datetimeToString(origDate) + " to " +
		 datetimeToString(newDate) + ".");
		 
    // Get rid of the current block.
    block.group.destroy();
    block.clean = true;
  } else {
    printMessage(block.ident + " slot move failed.", "error");
    block.moving = false;
    // Move it back to where it was.
    block.redrawRequired = true;
  }

  scheduleUpdated();
};


// Function that draws a scheduled block.
const drawBlock = function(proj, slot) {
  // Return immediately if the block isn't scheduled.
  if ((typeof proj == "undefined") || (typeof slot == "undefined")) {
    return;
  }

  if (proj.slot[slot].scheduled == 0) {
    return;
  }

  // Check if this block has already been drawn.
  var bo = findBlockObject(proj, slot);
  if ((bo != null) && (!bo.redrawRequired)) {
    return;
  } else if ((bo != null) && (bo.redrawRequired)) {
    // Redraw it the way it has already been specified.
    bo.group.absolutePosition(bo.absolutePosition);
    bo.redrawRequired = false;
    return;
  }
  
  // Split the block up into drawing blocks, one for each day.
  // Get the day that we start on.
  var startDayIdx = calcDayNumber(
    easternStandardTime(proj.slot[slot].scheduled_start * 1000)) - 1;
  // And the day that we end on.
  var endDayIdx = calcDayNumber(
    easternStandardTime(endingDate(proj, slot))) - 1;

  var blockGroup = new Konva.Group({
    draggable: false
  });
  var blockRectOpts = [];
  var blockRects = [];
  var blockTextOpts = [];
  var blockTexts = [];
  
  for (var i = startDayIdx; i <= endDayIdx; i++) {
    // Get the time range on this day.
    var d1 = allDates[i].getTime() / 1000;
    var d2 = allDates[i + 1].getTime() / 1000;
    var s1 = d1;
    var ts1 = easternStandardTime(proj.slot[slot].scheduled_start * 1000)
    if (ts1 > s1) {
      s1 = ts1;
    }
    var s2 = d2;
    var ed = endingDate(proj, slot);
    var et = easternStandardTime(ed);
    if (et < s2) {
      s2 = et;
    }
    // Now the start and end half hours.
    var hh1 = (s1 - d1) / 1800;
    var hh2 = (s2 - d1) / 1800;
    if ((hh2 - hh1) == 0) {
      // This is zero time (probably finished at midnight).
      // We don't draw this.
      continue;
    }
    // And let's draw the block.
    var blockOpts = {
      x: (meas.marginLeft + meas.dayLabelWidth + hh1 * meas.halfHourWidth),
      y: (meas.marginTop + i * meas.dayHeight),
      width: (hh2 - hh1) * meas.halfHourWidth, height: meas.dayHeight,
      stroke: normalBlockColour, strokeWidth: normalBlockStroke
    };
    var block = new Konva.Rect(blockOpts);
    blockRectOpts.push(blockOpts);
    blockRects.push(block);
    blockGroup.add(block);
    // Draw the background colours.
    for (var j = hh1; j < hh2; j++) {
      var ti = Math.floor(j / 2);
      fillColour = "#" + proj.colour;
      if (ti % 2) {
	fillColour = "#ffffff";
      }
      var hhRectOpts = {
	x: (meas.marginLeft + meas.dayLabelWidth + j * meas.halfHourWidth),
	y: (meas.marginTop + i * meas.dayHeight + 1),
	width: meas.halfHourWidth, height: (meas.dayHeight - 2),
	fill: fillColour, stroke: fillColour, strokeWidth: 0
      };
      if (j == hh1) {
	hhRectOpts.x += 1;
	hhRectOpts.width -= 1;
      } else if (j == (hh2 - 1)) {
	hhRectOpts.width -= 1;
      }
      var halfHourRect = new Konva.Rect(hhRectOpts);
      blockGroup.add(halfHourRect);
    }
    // Draw the necessary text.
    var mainTitleOpts = {
      x: (blockOpts.x + blockOpts.width / 2),
      y: (blockOpts.y + blockOpts.height / 2),
      text: proj.ident + " (" + proj.PI + ")",
      fontSize: 16, fill: "black",
      type: "main", textPattern: "full"
    };
    if (proj.ident == "MAINT") {
      mainTitleOpts.text = proj.title;
      mainTitleOpts.textPattern = "full";
    } else if (proj.ident == "CONFIG") {
      mainTitleOpts.text = "Reconfigure #" + proj.slot[slot].source +
	"/Calibration";
      mainTitleOpts.textPattern = "full";
    } else if (proj.ident == "CABB") {
      mainTitleOpts.text = "CABB";
      mainTitleOpts.textPattern = "full";
    }
    blockTextOpts.push(mainTitleOpts);
    var mainTitleText = new Konva.Text(mainTitleOpts);
    
    // Check if this text fits.
    var tw = (mainTitleText.width() + 2 * meas.textOffset);
    var fits = (tw < blockOpts.width);
    while (!fits) {
      // Try to shrink the text first.
      if (mainTitleOpts.fontSize > 12) {
	mainTitleOpts.fontSize -= 1;
	mainTitleText.fontSize(mainTitleOpts.fontSize);
      } else {
	// We change the pattern.
	mainTitleOpts.fontSize = 16;
	mainTitleText.fontSize(mainTitleOpts.fontSize);
	if (mainTitleOpts.textPattern == "full") {
	  // Shrink to short.
	  mainTitleOpts.textPattern = "short";
	  if (proj.ident == "MAINT") {
	    mainTitleOpts.text = "Maint";
	  } else if (proj.ident == "CONFIG") {
	    mainTitleOpts.text = "Reconf #" + proj.slot[slot].source;
	  } else if (proj.ident == "CABB") {
	    // Do nothing.
	    mainTitleOpts.text = "CABB";
	  } else {
	    // Just the project code.
	    mainTitleOpts.text = proj.ident;
	  }
	  mainTitleText.text(mainTitleOpts.text);
	} else if (mainTitleOpts.textPattern == "short") {
	  // We move to vertical.
	  mainTitleOpts.textPattern = "vertical";
	  mainTitleOpts.fontSize = 16;
	  mainTitleText.fontSize(mainTitleOpts.fontSize);
	  if (proj.ident == "MAINT") {
	    mainTitleOpts.text = "M/T";
	  } else if (proj.ident == "CONFIG") {
	    mainTitleOpts.text = "R/C";
	  } else if (proj.ident == "CABB") {
	    // Still the same.
	    mainTitleOpts.text = "CABB";
	  } else {
	    // Still just the ident.
	    mainTitleOpts.text = proj.ident;
	  }
	  mainTitleText.text(mainTitleOpts.text);
	  mainTitleText.rotation(-90);
	} else {
	  break;
	}
      }
      tw = (mainTitleText.width() + 2 * meas.textOffset);
      if (mainTitleOpts.textPattern == "vertical") {
	fits = (tw < blockOpts.height);
      } else {
	fits = (tw < blockOpts.width);
      }
    }
    mainTitleText.offsetX(mainTitleText.width() / 2 - meas.textOffset);
    mainTitleText.offsetY(mainTitleText.height() / 2 - meas.textOffset);
    
    blockTexts.push(mainTitleText);
    blockGroup.add(mainTitleText);

    // More text for the ASTRO blocks.
    if (proj.type == "ASTRO") {
      var sourceTextOpts = {
	x: blockOpts.x, y: blockOpts.y,
	text: proj.slot[slot].source,
	fontSize: meas.supportFontSize,
	fill: "black", type: "source"
      };
      var sourceText = new Konva.Text(sourceTextOpts);
      var bandTextOpts = {
	x: (blockOpts.x + blockOpts.width),
	y: (blockOpts.y + blockOpts.height),
	text: "(" + proj.slot[slot].bands.join(" ") + ")",
	fontSize: meas.supportFontSize,
	fill: "black", type: "band"
      };
      var bandText = new Konva.Text(bandTextOpts);
      var modeTextOpts = {
	x: (blockOpts.x + blockOpts.width),
	y: blockOpts.y,
	text: "(" + proj.slot[slot].bandwidth + ")",
	fontSize: meas.supportFontSize,
	fill: "black", type: "bandwidth"
      };
      var modeText = new Konva.Text(modeTextOpts);
      var supportTextOpts = null;
      if (legacyProjects.indexOf(proj.ident) >= 0) {
	supportTextOpts = {
	  x: blockOpts.x,
	  y: (blockOpts.y + blockOpts.height),
	  text: "LEGACY",
	  fontSize: meas.supportFontSize,
	  fill: "black", "type": "legacy"
	};
      }
      var supportText = null;
      if (supportTextOpts != null) {
	supportText = new Konva.Text(supportTextOpts);
      }
      // Change what we display based on what fits.
      var sw = sourceText.width();
      var bw = bandText.width();
      var showSource = false;
      var showBand = false;
      // Prioritise the source and the band.
      if ((sw + (2 * meas.textOffset)) < blockOpts.width) {
	showSource = true;
      }
      if ((bw + (2 * meas.textOffset)) < blockOpts.width) {
	showBand = true;
      }
      // If possible we display the mode and the support.
      var mw = modeText.width();
      var showMode = false;
      var showSupport = false;
      var pw = 0;
      if (supportText != null) {
	pw = supportText.width();
      }
      if (showSource) {
	if ((mw + sw + (4 * meas.textOffset)) < blockOpts.width) {
	  showMode = true;
	}
      }
      if (showBand && (pw > 0)) {
	if ((pw + bw + (4 * meas.textOffset)) < blockOpts.width) {
	  showSupport = true;
	}
      }

      if (showSource) {
	sourceText.offsetX(-1 * meas.textOffset);
	sourceText.offsetY(-1 * meas.textOffset);
	blockTexts.push(sourceText);
	blockGroup.add(sourceText);
      } else {
	sourceText.destroy();
      }
      if (showMode) {
	modeText.offsetX(mw + meas.textOffset);
	modeText.offsetY(-1 * meas.textOffset);
	blockTexts.push(modeText);
	blockGroup.add(modeText);
      } else {
	modeText.destroy();
      }
      if (showBand) {
	bandText.offsetX(bw + meas.textOffset);
	bandText.offsetY(bandText.height() + meas.textOffset);
	blockTexts.push(bandText);
	blockGroup.add(bandText);
      } else {
	bandText.destroy();
      }
      if (showSupport) {
	supportText.offsetX(-1 * meas.textOffset);
	supportText.offsetY(supportText.height() + meas.textOffset);
	blockTexts.push(supportText);
	blockGroup.add(supportText);
      } else if (supportText != null) {
	supportText.destroy();
      }
    }

  }
  blockLayer.add(blockGroup);
  
  // Add this block to the block object array.
  var blockAddition = {
    ident: proj.ident, slot: slot, clean: false, moving: false,
    group: blockGroup, rects: blockRects, rectOpts: blockRectOpts,
    textOptions: blockTextOpts, texts: blockTexts,
    redrawRequired: false, absolutePosition: blockGroup.absolutePosition()
  };
  blockObjects.push(blockAddition);
  // Make this respond to dragging.
  blockGroup.on("dragend", dragConstructor(blockAddition));
  
};

const drawConfiguration = function(title, start, end) {
  // Round off the start and end times.
  var nDaysSinceStart;
  if (start == scheduleFirst.getTime() / 1000) {
    nDaysSinceStart = 0;
  } else {
    nDaysSinceStart = Math.ceil((start - (scheduleFirst.getTime() / 1000)) /
				86400) - 0.5;
  }

  var endDaysSinceStart;
  if (end == scheduleLast.getTime() / 1000) {
    endDaysSinceStart = Math.ceil(((scheduleLast.getTime() / 1000) - start) /
				  86400) - 0.5 + nDaysSinceStart;
  } else {
    endDaysSinceStart = Math.ceil((end - (scheduleFirst.getTime() / 1000)) /
				  86400) - 0.5;
  }
  
  // Draw a box on the right.
  var nDays = endDaysSinceStart;
  var boxLeft = meas.marginLeft + meas.dayLabelWidth + meas.dayWidth;
  var boxTop = meas.marginTop + nDaysSinceStart * meas.dayHeight;
  var boxWidth = meas.arrayLabelWidth;
  var boxHeight = (nDays - nDaysSinceStart) * meas.dayHeight;
  
  var arrayBoxOpts = {
    x: boxLeft, y: boxTop, width: boxWidth, height: boxHeight,
    stroke: "black", strokeWidth: 2, fill: "#ffffff"
  };
  var arrayBox = new Konva.Rect(arrayBoxOpts);
  arrayGroup.add(arrayBox);

  // Create the label. We repeat it every two weeks if required.
  var limitHeight = 14 * meas.dayHeight;
  var totalHeight = 0;
  while (boxHeight > 0) {
    var labelHeight = (boxHeight > limitHeight) ? limitHeight : boxHeight;
    var arrayLabelString = new Konva.Text({
      x: boxLeft, y: boxTop + totalHeight, width: boxWidth, height: labelHeight,
      align: "center", verticalAlign: "middle", text: title.toUpperCase(),
      fontSize: 20
    });
    totalHeight += labelHeight;
    boxHeight -= labelHeight;
    arrayGroup.add(arrayLabelString);
  }
  
};

// Function that draws the n-th day in the schedule.
// Takes the day number n, the Date d and the group g to draw to.
// Can optionally make cross-hatched areas with colour c and
// start,end time pairs listed in t. If you don't want that, ensure
// t is undefined.
// If the date box doesn't need to be redrawn, set dd to false.
const drawDay = function(n, d, g, dd, c, t, g2) {
  if (dd == true) {
    // The date is shown in the day label box.
    var dayLabelOpts = {
      x: meas.marginLeft, y: (meas.marginTop + n * meas.dayHeight),
      width: meas.dayLabelWidth, height: meas.dayHeight,
      stroke: "black", strokeWidth: 2, fill: '#ffffff'
    };
    // Colour the weekends differently.
    if ((d.getDay() == 0) || (d.getDay() == 6)) {
      dayLabelOpts.fill = "#ff9a8d";
    }
    var dayLabelBox = new Konva.Rect(dayLabelOpts);
    // Make the string to go into this box.
    var dateString = new Konva.Text({
      x: meas.marginLeft + 5, y: (meas.marginTop + n * meas.dayHeight),
      text: printDate(d), fontSize: 16, verticalAlign: "middle",
      height: meas.dayHeight
    });
    // Draw the outline of the box for the hours.
    var dayBox = new Konva.Rect({
      x: meas.marginLeft + meas.dayLabelWidth, y: (meas.marginTop + n * meas.dayHeight),
      width: meas.dayWidth, height: meas.dayHeight,
      stroke: "black", strokeWidth: 2
    });
    g.add(dayLabelBox);
    g.add(dateString);
    g.add(dayBox);
    
    // Draw an hour grid.
    for (var j = 0; j < 24; j++) {
      fillColour = "#" + scheduleData.program.colours.unscheduled;
      if (j % 2) {
	fillColour = "#ffffff";
      }
      var hourRect = new Konva.Rect({
	x: (meas.marginLeft + meas.dayLabelWidth + j * 2 * meas.halfHourWidth),
	y: (meas.marginTop + n * meas.dayHeight + 1),
	width: (2 * meas.halfHourWidth), height: (meas.dayHeight - 2),
	fill: fillColour, stroke: fillColour, strokeWidth: 0
      });
      g.add(hourRect);
    }
  }

  // Make the cross-hatching if asked to.
  if (typeof t != "undefined") {
    for (var i = 0; i < t.length; i++) {
      var leftx = meas.marginLeft + meas.dayLabelWidth +
	  t[i][0] * 2 * meas.halfHourWidth;
      var rightx = meas.marginLeft + meas.dayLabelWidth +
	  t[i][1] * 2 * meas.halfHourWidth;
      var dx = rightx - leftx;
      var coverageBox = new Konva.Rect({
	x: leftx, y: (meas.marginTop + n * meas.dayHeight + 1),
	width: dx, height: (meas.dayHeight - 2),
	fill: c, opacity: 0.7
      });
      g2.add(coverageBox);
    }
  }
};

// Function that draws the hour labels at the top of the schedule.
// Need to supply the group g to draw to.
const drawHourLabels = function(g) {
  for (var j = 0; j <= 24; j += 2) {
    var hourLabel = new Konva.Text({
      x: (meas.marginLeft + meas.dayLabelWidth + j * 2 * meas.halfHourWidth),
      y: meas.timeLabelHeight, text: "" + (j % 24), fontSize: 20
    });
    hourLabel.offsetX(hourLabel.width() / 2);
    hourLabel.offsetY(hourLabel.height() * 1.1);
    g.add(hourLabel);
    var utcLabel = new Konva.Text({
      x: (meas.marginLeft + meas.dayLabelWidth + j * 2 * meas.halfHourWidth),
      y: meas.timeLabelHeight, text: "" + ((j + 14) % 24), fontSize: 20
    });
    utcLabel.offsetX(utcLabel.width() / 2);
    utcLabel.offsetY(utcLabel.height() * 2.2);
    g.add(utcLabel);
  }
};

// Draw a polygon to show when it's night times.
const drawNightTimes = function(t, g) {
  var morningPos = [ meas.marginLeft + meas.dayLabelWidth, meas.marginTop ];
  var eveningPos = [ meas.marginLeft + meas.dayLabelWidth +
		     48 * meas.halfHourWidth, meas.marginTop ];
  for (i = 0; i < (t.length - 2); i++) {
    var y = meas.marginTop + i * meas.dayHeight;
    morningPos.push(meas.marginLeft + meas.dayLabelWidth +
		    t[i].rise * (2 * meas.halfHourWidth));
    morningPos.push(y);
    eveningPos.push(meas.marginLeft + meas.dayLabelWidth +
		    t[i].set * (2 * meas.halfHourWidth));
    eveningPos.push(y);
  }
  morningPos.push(meas.marginLeft + meas.dayLabelWidth);
  morningPos.push(meas.marginTop + (nDays - 1) * meas.dayHeight);
  eveningPos.push(meas.marginLeft + meas.dayLabelWidth + 48 * meas.halfHourWidth);
  eveningPos.push(meas.marginTop + (nDays - 1) * meas.dayHeight);
  var morningPoly = new Konva.Line({
    points: morningPos, fill: "#888888", stroke: "#888888", strokeWidth: 0,
    closed: true, opacity: 0.7
  });
  var eveningPoly = new Konva.Line({
    points: eveningPos, fill: "#888888", stroke: "#888888", strokeWidth: 0,
    closed: true, opacity: 0.7
  });
  g.add(morningPoly);
  g.add(eveningPoly);
};

// This routine generates a transform callback.
const genBlockTransform = function(block, rectIndex) {
  return function() {
    transformBlock(block, rectIndex);
  };
};

// Highlight a selected schedule block.
const highlightBlock = function(proj, slot) {
  var bo = findBlockObject(proj, slot);
  for (var i = 0; i < bo.rects.length; i++) {
    bo.rects[i].stroke(highlightedBlockColour);
    bo.rects[i].strokeWidth(highlightedBlockStroke);
    // Attach the transformers.
    if (i == 0) {
      transformerTop.attachTo(bo.rects[i]);
      if (i < (bo.rects.length - 1)) {
	// There is another block after this, so we don't
	// allow the end time to be changed.
	transformerTop.enabledAnchors([ 'middle-left' ]);
      } else {
	transformerTop.enabledAnchors([ 'middle-left', 'middle-right' ]);
      }
      bo.rects[i].on('transformend', genBlockTransform(bo, i));
      if (bo.rects.length == 1) {
	// Ensure the bottom transformer has been detached.
	transformerBottom.detach();
      }
    } else if (i == (bo.rects.length) - 1) {
      transformerBottom.attachTo(bo.rects[i]);
      // We never want to be able to move the start time of these
      // type of blocks.
      transformerBottom.enabledAnchors([ 'middle-right' ]);
      bo.rects[i].on('transformend', genBlockTransform(bo, i));
    }
  }
  bo.group.moveToTop();
  // Make it possible to drag this block now.
  bo.group.draggable(true);
  blockLayer.draw();
};

// Draw an LST line on a particular day.
const lstDraw = function(n, d, l, p, g) {
  // Calculate the LST at midnight this day.
  var zlst = 24 * mjd2lst(date2mjd(d), (149.5501388 / 360.0), 0);
  var midHours = hoursUntilLst(zlst, l);
  var topHours = midHours + (2 / 60);
  var bottomHours = midHours - (2 / 60);
  var topX = meas.marginLeft + meas.dayLabelWidth + (topHours * (2 * meas.halfHourWidth));
  var bottomX = meas.marginLeft + meas.dayLabelWidth + (bottomHours * (2 * meas.halfHourWidth));
  var lobj = p;
  lobj.points = [ topX, (meas.marginTop + n * meas.dayHeight),
		  bottomX, (meas.marginTop + (n + 1) * meas.dayHeight) ];
  lobj.strokeWidth = 4;
  var line = new Konva.Line(lobj);
  g.add(line);
};

// Relabel all the reconfiguration blocks, according to their new
// numbers.
const relabelReconfigs = function() {
  var configs = getProjectByName("CONFIG");
  var slots = configs.details.slot;

  for (var i = 1; i < slots.length; i++) {
    if (slots[i].scheduled == 1) {
      var bo = findBlockObject(configs.details, i);
      if (bo != null) {
	for (var j = 0; j < bo.textOptions.length; j++) {
	  if (bo.textOptions[j].type == "main") {
	    if (bo.textOptions[j].textPattern == "full") {
	      bo.textOptions[j].text = "Reconfigure #" +
		slots[i].source + "/Calibration";
	    } else if (bo.textOptions[j].textPattern == "short") {
	      bo.textOptions[j].text = "Reconf #" + slots[i].source;
	    }
	    bo.texts[j].text(bo.textOptions[j].text);
	  }
	}
      }
    }
  }
};

// Do all the things needed to create the canvas, after the schedule
// has been loaded.
const setupCanvas = function(data) {

  // Set up the schedule.
  var re = /^(\d\d\d\d)(\D\D\D)$/g;
  var rmatch = re.exec(data.program.term.term);
  var semester = rmatch[2]
  var year = parseInt(rmatch[1]);

  // Get the date for the first day of the schedule.
  var semesterStartMonth = -1;
  if (semester == "APR") {
    semesterStartMonth = 4;
  } else if (semester == "OCT") {
    semesterStartMonth = 10;
  }
  semesterStart.setFullYear(year, (semesterStartMonth - 1), 1);
  semesterStart.setHours(0);
  //semesterStart.setHours(14);
  // Subtract a few days.
  scheduleFirst = new Date();
  scheduleFirst.setTime(semesterStart.getTime() - 3 * 86400 * 1000);
  // Make all the dates.
  var allSunDates = [];
  for (var i = -1; i <= nDays; i++) {
    var pdate = new Date();
    pdate.setTime(scheduleFirst.getTime() + i * 86400 * 1000);
    allSunDates.push(pdate);
  }
  allDates = allSunDates.slice(1, nDays);
  scheduleLast = new Date();
  scheduleLast.setTime(allDates[allDates.length - 1].getTime() + 86400 * 1000);
  
  // Set up the canvas.
  stage = new Konva.Stage({
    container: "schedtable",
    width: meas.width, height: meas.height
  });

  // Make the stage respond to clicks.
  stage.on("click", handleCanvasClick);
  
  var hourStage = new Konva.Stage({
    container: "schedtabletop",
    width: meas.width, height: meas.timeLabelHeight
  });
  // Make a layer for the time labels.
  var timeLayer = new Konva.Layer();
  // And we need a group.
  var timeLabelGroup = new Konva.Group({
    draggable: false
  });
  // Draw the hour labels at the top.
  drawHourLabels(timeLabelGroup);
  // Add this to the stage.
  timeLayer.add(timeLabelGroup);
  hourStage.add(timeLayer);
  
  // Make the background layer.
  backgroundLayer = new Konva.Layer();
  // Add to this a group which will contain all the day boxes.
  var dayBoxGroup = new Konva.Group({
    draggable: false
  });

  constraintLayer = new Konva.Layer();
  constraintBoxGroup = new Konva.Group({
    draggable: false
  });
  constraintLayer.add(constraintBoxGroup);
  
  allDates.forEach(function(d, i) {
    drawDay(i, d, dayBoxGroup, true);
  });
  // Add the background groups and layer to the stage.
  backgroundLayer.add(dayBoxGroup);
  stage.add(backgroundLayer);
  stage.add(constraintLayer);

  // Make the top layer, which will be for the LST and daylight.
  var topLayer = new Konva.Layer();
  // The group here will contain all the lines for LST, and the
  // shaded night area.
  var timeGroup = new Konva.Group({
    draggable: false
  });
  
  // For each day draw the LST.
  var lstLines = [ 0, 6, 12, 18 ];
  var lstProps = [ { stroke: 'red' },
		   { stroke: 'blue', dash: [ 24, 11 ] },
		   { stroke: 'orange', dash: [ 24, 11 ] },
		   { stroke: '#ee82ee', dash: [ 24, 11 ] } ];
  for (var i = 0; i < lstLines.length; i++) {
    allDates.forEach(function(d, j) {
      lstDraw(j, allDates[j], lstLines[i], lstProps[i], timeGroup);
    });
  }
  
  var nightGroup = new Konva.Group({
    draggable: false
  });
  // Calculate the sunrise/sunset time for each day.
  var sunTimes = allSunDates.map(calculateSunStuff);
  drawNightTimes(sunTimes, nightGroup);
  
  topLayer.add(nightGroup);
  topLayer.add(timeGroup);
  stage.add(topLayer);

  // Add the side layer for the array configuration.
  arrayLayer = new Konva.Layer();
  arrayGroup = new Konva.Group({
    draggable: false
  });
  arrayLayer.add(arrayGroup);
  stage.add(arrayLayer);
  
  // And the layer for the schedule blocks.
  blockLayer = new Konva.Layer();
  // Make the transformers.
  var transformerOptions = {
    rotateEnabled: false,
    borderEnabled: true,
    borderStroke: highlightedBlockColour,
    borderStrokeWidth: highlightedBlockStroke,
    enabledAnchors: [ "middle-left", "middle-right" ],
    keepRatio: false
  };
  transformerTop = new Konva.Transformer(transformerOptions);
  blockLayer.add(transformerTop);
  transformerBottom = new Konva.Transformer(transformerOptions);
  blockLayer.add(transformerBottom);
  stage.add(blockLayer);
  
  // Draw the initial array configurations.
  orderReconfigs();
  drawArrayConfigurations();

  // Draw all the blocks we know about already.
  drawAllBlocks();
};

// This routine gets called when a block has been transformed.
const transformBlock = function(block, rectIndex) {
  var rect = block.rects[rectIndex];
  var timen = posTime(rect.x(), rect.y());
  // Set the current block to moving so we don't consider it
  // during the resize.
  block.move = true;
  var scheduled = false;
  var hoursDuration = 0;
  if ((rectIndex == 0) && (block.rects.length == 1)) {
    // We're resizing the only rectangle.
    hoursDuration = Math.round((rect.width() * rect.scaleX()) /
			       meas.halfHourWidth) / 2;
  } else {
    // We have to work out how many extra hours were added or
    // subtracted.
    for (var i = 0; i < block.rects.length; i++) {
      hoursDuration += Math.round((block.rects[i].width() *
				   block.rects[i].scaleX()) /
				  meas.halfHourWidth) / 2;
    }
    if (rectIndex > 0) {
      // We're resizing the last rectangle. We have to get the start time
      // from the first rectangle.
      timen = posTime(block.rects[0].x(), block.rects[0].y());
    }
  }
  scheduled = scheduleInsert(block.ident, block.slot, timen, true,
			     hoursDuration);
  if (scheduled != null) {
    // Get rid of the current block.
    block.group.destroy();
    block.clean = true;
  } else {
    block.moving = false;
    block.redrawRequired = true;
  }
};

// Get rid of a block on the canvas.
const undrawBlock = function(proj, slot) {
  // Return immediately if the block isn't scheduled.
  if ((typeof proj == "undefined") || (typeof slot == "undefined")) {
    return;
  }

  if (proj.slot[slot].scheduled == 0) {
    return;
  }

  // Check if this block has already been drawn.
  var bo = findBlockObject(proj, slot);
  if (bo == null) {
    return;
  }

  // Get rid of it.
  bo.group.destroy();
  removeBlockObject(proj, slot);
  
};



/********************************************************************
 * SCHEDULE FUNCTIONS
 * These functions load, save or modify the schedule in some way.
 */

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

// Draw all the blocks.
const drawAllBlocks = function() {
  var allProjects = scheduleData.program.project;
  for (var i = 0; i < allProjects.length; i++) {
    var slots = allProjects[i].slot;
    for (var j = 0; j < slots.length; j++) {
      if (slots[j].scheduled == 1) {
	drawBlock(allProjects[i], j);
	// Check if we are selected.
	if ((previouslySelectedProject != null) &&
	    (allProjects[i].ident == previouslySelectedProject.details.ident) &&
	    (j == previouslySelectedSlot)) {
	  // Highlight this block.
	  highlightBlock(allProjects[i], j);
	}
      }
    }
  }
  blockLayer.draw();
};

// Return the end time of a particular project and slot as a Date.
const endingDate = function(proj, slot) {
  if ((typeof proj == "undefined") || (typeof slot == "undefined")) {
    return null;
  }

  if (proj.slot[slot].scheduled == 1) {
    var schedend = proj.slot[slot].scheduled_start +
	(proj.slot[slot].scheduled_duration * 3600);
    return new Date(schedend * 1000);
  }

  return null;
};

// Return the earliest scheduled time from a list of projects.
const getEarliestDate = function(slotList) {
  if (slotList.length == 0) {
    return null;
  }

  var earliest = -1;
  for (var i = 0; i < slotList.length; i++) {
    if (slotList[i].project.slot[slotList[i].slot].scheduled == 1) {
      if (earliest == -1) {
	earliest = slotList[i].project.slot[slotList[i].slot]
	  .scheduled_start;
      } else if (slotList[i].project.slot[slotList[i].slot]
		 .scheduled_start < earliest) {
	earliest = slotList[i].project.slot[slotList[i].slot]
	  .scheduled_start;
      }
    }
  }

  if (earliest == -1) {
    return null;
  }

  return new Date(earliest * 1000);
};

// Load the schedule JSON file.
const loadFile = function(callback, forceServer) {
  // We don't do anything if we haven't checked for a local file.
  if (!localChecked) {
    return;
  }

  // If we're not online and we have no local file, we can't do anything.
  if ((localChecked) && (!navigator.onLine) && (localModificationTime == null)) {
    return;
  }

  // If we've just started, we're online but we haven't heard
  // from the server, we wait.
  if ((localChecked) && (navigator.onLine) && (serverModificationTime == null)) {
    return;
  }
  
  // If we're not online, we load the local file.
  var loadLocal = null;
  if (!navigator.onLine) {
    loadLocal = true;
  } else {
    // We work out which to load based on their modification times.
    if (localModificationTime == null) {
      // We have to load the server version.
      loadLocal = false;
    } else if (localModificationTime > serverModificationTime) {
      // We load the local version as it's more recent.
      loadLocal = true;
    } else {
      // We load the server version as it's more recent.
      loadLocal = false;
    }
  }

  if (forceServer == true) {
    loadLocal = false;
  }
  
  if (loadLocal == true) {
    printMessage("Loading local schedule.");
    callback(null, getLocalSchedule());
  } else if (loadLocal == false) {
    var msg = "Loading server schedule for " + obsNames[obs];
    // We get the file from a CGI script.
    var xhr = new XMLHttpRequest();
    var gstring = "?request=load&observatory=" + obs;
    if (semester != null) {
      gstring += "&term=" + semester;
      msg += " " + semester;
    }
    printMessage(msg + ".");
    xhr.open('GET', spath + gstring, true);
    xhr.responseType = "json";
    xhr.onload = function() {
      var status = xhr.status;
      if (status === 200) {
	callback(null, cleanjson(xhr.response));
      } else {
	callback(status, xhr.response);
      }
    };
    xhr.send();
  } else {
    // What??
    printMessage("Could not load the server schedule.", "error");
  }
};

// This function numbers all the reconfigurations based on their
// current ordering.
const orderReconfigs = function() {
  var configs = getProjectByName("CONFIG");
  var slots = configs.details.slot;

  // We ignore the first configuration, since it is the one we start
  // with.
  var rconfigs = slots.slice(1);
  // Sort these according to start time.
  rconfigs.sort(function(a, b) {
    return (a.scheduled_start - b.scheduled_start);
  });

  var cnumber = scheduleData.program.special.lastReconfigNumber + 1;
  for (var i = 0; i < rconfigs.length; i++) {
    if (rconfigs[i].scheduled == 1) {
      rconfigs[i].source = "" + cnumber;
      cnumber += 1;
    }
  }

  // Call for all the reconfig blocks to be relabelled.
  relabelReconfigs();
};

// This function gets called if the user changes the state of the
// LST restrictions check box or text inputs.
const lstRestrictionsChange = function() {
  // Check if we have a project and slot selected.
  var ul = document.getElementById("sourceUseLST");
  var riseInp = document.getElementById("sourceLSTRise");
  var setInp = document.getElementById("sourceLSTSet");
  if ((previouslySelectedProject == null) ||
      (previouslySelectedSlot == null)) {
    // Deselect the box.
    ul.checked = false;
    // Clear the inputs.
    riseInp.value = "";
    setInp.value = "";
    return;
  }

  // Get the current state.
  var lc = (ul.checked) ? 1 : 0;
  var rise = riseInp.value;
  var set = setInp.value;
  // Check for changes.
  var psps = previouslySelectedProject.details.slot[previouslySelectedSlot];
  if ((psps.lst_limits_used != lc) ||
      (psps.lst_start != rise) ||
      (psps.lst_end != set)) {
    // Change the things that need changing.
    if (psps.lst_limits_used != lc) {
      psps.lst_limits_used = lc;
    }
    if (psps.lst_start != rise) {
      psps.lst_start = rise;
    }
    if (psps.lst_end != set) {
      psps.lst_end = set;
    }
    updateLocalSchedule();
    // Reselect this slot to redraw the constraints.
    selectSlot(previouslySelectedSlot);
  }
  
};

// Return the project and slot scheduled at a specified time, or
// null if nothing is.
const scheduledAt = function(d) {
  var allProjects = scheduleData.program.project;
  for (var i = 0; i < allProjects.length; i++) {
    var slots = allProjects[i].slot;
    for (var j = 0; j < slots.length; j++) {
      if (slots[j].scheduled == 1) {
	// Check we aren't looking at the currently selected block.
	if ((previouslySelectedProject != null) &&
	    (previouslySelectedSlot != null) &&
	    (allProjects[i].ident == previouslySelectedProject.details.ident) &&
	    (j == previouslySelectedSlot)) {
	  continue;
	}
	var tdiff;
	if (d instanceof Date) {
	  tdiff = (d.getTime() / 1000) - slots[j].scheduled_start;
	} else {
	  tdiff = d - slots[j].scheduled_start;
	}
	if ((tdiff >= 0) && (tdiff < (slots[j].scheduled_duration * 3600))) {
	  // This is what we're looking for.
	  return { 'project': allProjects[i],
		   'slot': j };
	}
      }
    }
  }
  return null;
};

// Return a list of projects scheduled between two dates, or an empty
// list if nothing is.
const scheduledBetween = function(d1, d2) {
  var allProjects = scheduleData.program.project;
  var projectsFound = [];
  var td1 = d1.getTime() / 1000;
  var td2 = d2.getTime() / 1000;
  for (var i = 0; i < allProjects.length; i++) {
    var slots = allProjects[i].slot;
    for (var j = 0; j < slots.length; j++) {
      if (slots[j].scheduled == 1) {
	// Check we aren't looking at the currently selected block.
	if ((previouslySelectedProject != null) &&
	    (previouslySelectedSlot != null) &&
	    (allProjects[i].ident == previouslySelectedProject.details.ident) &&
	    (j == previouslySelectedSlot)) {
	  continue;
	}
	var ts1 = slots[j].scheduled_start;
	var slotEnd = endingDate(allProjects[i], j);
	var ts2 = slotEnd.getTime() / 1000;
	if (((td1 >= ts1) && (td1 < ts2)) ||
	    ((td2 >= ts1) && (td2 < ts2)) ||
	    ((td1 < ts1) && (td2 > ts2))) {
	  // This slot conflicts.
	  projectsFound.push({ 'project': allProjects[i],
			       'slot': j });
	}
      }
    }
  }
  return projectsFound;
};

// A routine to do a bunch of things if the schedule gets updated.
const scheduleUpdated = function() {
  // First, save the schedule locally.
  updateLocalSchedule();

  // Now redraw the canvas.
  cleanBlockObjects();
  orderReconfigs();
  drawArrayConfigurations();
  // Draw all the blocks again.
  drawAllBlocks();
  
  // Now redraw all the tables.
  updateAllTables();
};

// Make a summary of the current state of the projects.
const summariseProjects = function() {
  var r = [];

  var allProjects = scheduleData.program.project;
  for (var i = 0; i < allProjects.length; i++) {
    var s = { 'ident': allProjects[i].ident, isNapa: false };
    if (/^NAPA/.test(allProjects[i].title)) {
      s.isNapa = true;
    }
    var slots = allProjects[i].slot;
    s.requestedSlots = slots.length;
    s.scheduledSlots = 0;
    s.requestedTime = 0;
    s.scheduledTime = 0;
    s.rating = 0;
    if (allProjects[i].hasOwnProperty("colour")) {
      s.colour = allProjects[i].colour;
    } else {
      s.colour = scheduleData.program.colours.default;
      allProjects[i].colour = s.colour;
    }
    for (var j = 0; j < slots.length; j++) {
      if (slots[j].scheduled == 1) {
	s.scheduledSlots++;
	s.scheduledTime += slots[j].scheduled_duration;
      }
      s.requestedTime += slots[j].requested_duration;
      if (slots[j].rating > s.rating) {
	s.rating = slots[j].rating;
      }
    }
    r.push(s);
  }

  return r;
};

// Make a summary of the array configurations required,
// and a general summary of the semester.
const summariseSemester = function() {
  var r = {};
  if (obs == "atca") {
    r = { 'arrays': [],
	  'timeSummary': {
	    'total': 0,
	    'maintenance': 0,
	    'vlbi': 0,
	    'calibration': 0,
	    'legacy': 0,
	    'available': 0,
	    'scheduled': 0,
	    'requested': 0,
	    'lowScore': 6,
	    'nCabb': 0,
	    'nReconfigure': 0
	  }, 'arrayLabels': [ { '6km': { 'a': "6A" } },
			      { '6km': { 'b': "6B" } },
			      { '6km': { 'c': "6C" } },
			      { '6km': { 'd': "6D" } },
			      { '6km': { 'any': "6*"} },
			      { '1.5km': { 'a': "1.5A" } },
			      { '1.5km': { 'b': "1.5B" } },
			      { '1.5km': { 'c': "1.5C" } },
			      { '1.5km': { 'd': "1.5D" } },
			      { '1.5km': { 'any': "1.5*" } },
			      { '750m': { 'a': "750A" } },
			      { '750m': { 'b': "750B" } },
			      { '750m': { 'c': "750C" } },
			      { '750m': { 'd': "750D" } },
			      { '750m': { 'any': "750*" } },
			      { 'compact': { 'ew367': "367" } },
			      { 'compact': { 'ew352': "352" } },
			      { 'compact': { 'any': "cmp" } },
			      { 'hybrid': { 'h214': "H214" } },
			      { 'hybrid': { 'h168': "H168" } },
			      { 'hybrid': { 'h75': "H75" } },
			      { 'hybrid': { 'any': "H*" } },
			      { 'any': { 'any': "*" } }
			    ]
	};
  } else if (obs == "parkes") {
    r = { 'arrays': [],
	  'timeSummary': {
	    'total': 0,
	    'maintenance': 0,
	    'vlbi': 0,
	    'calibration': 0,
	    'funded': 0,
	    'available': 0,
	    'scheduled': 0,
	    'requested': 0,
	    'lowScore': 6,
	    'nReconfigure': 0
	  }, 'arrayLabels': [ { 'uwl': "UWL" }, { 'mb': "MULTI" },
			      { 'mars': "MARS" }, { "k": "K" },
			      { 'ku': "KU" }, { '10/50': "10/50cm" } ]
	};
  }

  // The total time available for the semester (in hours).
  r.timeSummary.available = (semesterEnd.getTime() -
			     semesterStart.getTime()) / (1000 * 3600);

  // Make the array summary object for each different possible score.
  var minScore = 0.0;
  var maxScore = 5.0;
  var scoreInterval = 0.1;
  for (var score = minScore; score <= maxScore; score += scoreInterval) {
    if (obs == "atca") {
      r.arrays.push({ 'score': Math.floor(score * 10) / 10,
		      '6km': { 'a': 0, 'b': 0, 'c': 0, 'd': 0, 'any': 0 },
		      '1.5km': { 'a': 0, 'b': 0, 'c': 0, 'd': 0, 'any': 0 },
		      '750m': { 'a': 0, 'b': 0, 'c': 0, 'd': 0, 'any': 0 },
		      'compact': { 'ew367': 0, 'ew352': 0, 'any': 0 },
		      'hybrid': { 'h214': 0, 'h168': 0, 'h75': 0, 'any': 0 },
		      'any': { 'any': 0 }
		    });
    } else if (obs == "parkes") {
      r.arrays.push({ 'score': Math.floor(score * 10) / 10,
		      'uwl': 0, 'mb': 0, 'ku': 0, 'k': 0, '10/50': 0,
		      'mars': 0 });
    }
  }
  
  var allProjects = scheduleData.program.project;
  for (var i = 0; i < allProjects.length; i++) {
    var slots = allProjects[i].slot;
    var isCalibration = false;
    if (allProjects[i].ident == "C007") {
      isCalibration = true;
    }
    var isLegacy = false;
    if (legacyProjects.indexOf(allProjects[i].ident.toUpperCase()) >= 0) {
      isLegacy = true;
    }
    var isVlbi = false;
    if (allProjects[i].ident == "VLBI") {
      isVlbi = true;
    }
    var isMaintenance = false;
    if ((allProjects[i].ident == "MAINT") ||
	(allProjects[i].ident == "CONFIG") ||
	(allProjects[i].ident == "CABB")) {
      isMaintenance = true;
    }
    var isNapa = false;
    if (/^NAPA/.test(allProjects[i].title)) {
      isNapa = true;
    }
    
    var projectTotalTime = 0;
    for (var j = 0; j < slots.length; j++) {
      if (!isCalibration && !isLegacy && !isMaintenance && !isVlbi && !isNapa) {
	r.timeSummary.requested += slots[j].requested_duration;
	r.timeSummary.scheduled += slots[j].scheduled_duration;
	projectTotalTime += slots[j].scheduled_duration;
      } else if (isCalibration) {
	r.timeSummary.calibration += slots[j].scheduled_duration;
      } else if (isLegacy) {
	r.timeSummary.legacy += slots[j].scheduled_duration;
	projectTotalTime += slots[j].scheduled_duration;
      } else if (isVlbi) {
	r.timeSummary.vlbi += slots[j].scheduled_duration;
      } else if (isMaintenance) {
	r.timeSummary.maintenance += slots[j].scheduled_duration;
	if ((allProjects[i].ident == "CONFIG") && (slots[j].scheduled == 1)) {
	  r.timeSummary.nReconfigure += 1;
	} else if ((allProjects[i].ident == "CABB") &&
		   (slots[j].scheduled == 1)) {
	  r.timeSummary.nCabb += 1;
	}
      }

      if ((!isLegacy && (projectTotalTime >= projectLimit)) ||
	  (isLegacy && (projectTotalTime >= legacyLimit))) {
	continue;
      }
      
      // Add to the correct array.
      if (!isMaintenance && !isVlbi && !isNapa) {
	for (var sarr = 0; sarr < r.arrays.length; sarr++) {
	  if (slots[j].rating < r.arrays[sarr].score) {
	    break;
	  }
	  if (obs == "atca") {
	    if ((slots[j].array == "6a") || (slots[j].array == "6b") ||
		(slots[j].array == "6c") || (slots[j].array == "6d") ||
		(slots[j].array == "any6")) {
	      var v = slots[j].array.replace("6", "");
	      r['arrays'][sarr]["6km"][v] += slots[j].requested_duration;
	    } else if ((slots[j].array == "1.5a") ||
		       (slots[j].array == "1.5b") ||
		       (slots[j].array == "1.5c") ||
		       (slots[j].array == "1.5d") ||
		       (slots[j].array == "any1.5")) {
	      var v = slots[j].array.replace("1.5", "");
	      r['arrays'][sarr]["1.5km"][v] += slots[j].requested_duration;
	    } else if ((slots[j].array == "750a") ||
		       (slots[j].array == "750b") ||
		       (slots[j].array == "750c") ||
		       (slots[j].array == "750d") ||
		       (slots[j].array == "any750")) {
	      var v = slots[j].array.replace("750", "");
	      r['arrays'][sarr]["750m"][v] += slots[j].requested_duration;
	    } else if ((slots[j].array == "ew352") ||
		       (slots[j].array == "ew367") ||
		       (slots[j].array == "anycompact")) {
	      var v = slots[j].array.replace("compact", "");
	      r['arrays'][sarr]["compact"][v] += slots[j].requested_duration;
	    } else if ((slots[j].array == "h168") ||
		       (slots[j].array == "h214") ||
		       (slots[j].array == "h75")) {
	      var v = slots[j].array;
	      r['arrays'][sarr]["hybrid"][v] += slots[j].requested_duration;
	    } else if (/^h/.test(slots[j].array)) {
	      // This means some other hybrid combination: we put this as any.
	      r['arrays'][sarr]["hybrid"]['any'] += slots[j].requested_duration;
	    } else if (slots[j].array == "any") {
	      r['arrays'][sarr]['any']['any'] += slots[j].requested_duration;
	    } else {
	      console.log("found array string " + slots[j].array);
	      break;
	    }
	  } else if (obs == "parkes") {
	    var ps = slots[j].array;
	    if (!Array.isArray(slots[j].array)) {
	      ps = [ slots[j].array ];
	    }
	    for (var k = 0; k < ps.length; k++) {
	      var larr = ps[k].toLowerCase();
	      if (typeof r['arrays'][sarr][larr] != "undefined") {
		r['arrays'][sarr][larr] += slots[j].requested_duration;
	      } else {
		console.log("found array string " + larr);
	      }
	    }
	  }
	}
      }
    }
  }

  return r;
};

const versionChanged = function() {
  // Get the new version.
  var vn = document.getElementById("scheduleVersion");
  var versionNumber = parseInt(vn.value);

  scheduleData.program.term.version = versionNumber;
  updateLocalSchedule();
};




/********************************************************************
 * UNSORTED FUNCTIONS BELOW
 */










const selectSlot = function(slotnumber) {
  var psp = previouslySelectedProject.details;
  // Highlight the table element.
  var hid = "slotrow-" + psp.ident +
      "-" + slotnumber;
  fillId(hid, null, "slotSelected");
  // Dehighlight the previously selected slot.
  if ((previouslySelectedSlot != null) &&
      (previouslySelectedSlot != slotnumber)) {
    var pid = "slotrow-" + psp.ident +
	"-" + previouslySelectedSlot;
    fillId(pid, null, null, "slotSelected");
    if (psp.slot[previouslySelectedSlot].scheduled == 1) {
      dehighlightBlock(psp, previouslySelectedSlot);
    }
  }
  previouslySelectedSlot = slotnumber;

  // Fill in the table.
  var psps = psp.slot[previouslySelectedSlot];
  fillInput("sourceRightAscension", psps.position.ra);
  fillInput("sourceDeclination", psps.position.dec);
  fillInput("sourceLSTRise", psps.lst_start);
  fillInput("sourceLSTSet", psps.lst_end);
  var lstIndicator = document.getElementById("sourceUseLST");
  lstIndicator.checked = (psps.lst_limits_used == 0) ? false : true;
  
  // Remove any previous restrictions from the canvas.
  constraintBoxGroup.destroyChildren();
  
  // Work out the restrictions and put them on the canvas.
  // Begin with bad dates.
  for (var i = 0;
       i < psp.excluded_dates.length; i++) {
    // Which day needs drawing.
    var daynum = calcDayNumber(psp.excluded_dates[i]);
    drawDay(daynum, null, null, false, "red", [ [ 0, 24 ] ],
	    constraintBoxGroup);
  }
  // Then LST, if we're dealing with an ASTRO project.
  if (psp.type == "ASTRO") {
    var sourceTimes = allDates.forEach(function(d) {
      var daynum = calcDayNumber(d) - 1;
      var sourceRiseSets = null;
      if (psps.lst_limits_used == 1) {
	var lstRise = stringToDegrees(psps.lst_start, true) / 15;
	var lstSet = stringToDegrees(psps.lst_end, true) / 15;
	var ra = stringToDegrees(psps.position.ra, true) / 15;
	sourceRiseSets = lstToDaytime(lstRise, lstSet, ra, d);
      } else {
	sourceRiseSets = calculateSiderealRestrictions(
	  psps.position.ra, psps.position.dec, d);
      }
      var tplots = [ [ sourceRiseSets.rise, sourceRiseSets.set ] ];
      if (sourceRiseSets.rise > sourceRiseSets.set) {
	// Backwards order.
	tplots = [ [ sourceRiseSets.rise, 24 ], [ 0, sourceRiseSets.set ] ];
      }
      if (sourceRiseSets.alwaysUp) {
	tplots = [ [0, 24 ] ];
      }
      
      drawDay(daynum, null, null, false, "orange", tplots, constraintBoxGroup);
      return sourceRiseSets;
    });
  }

  constraintLayer.draw();
  
  // Scroll to the right place if we have it already
  // scheduled, or the first good date.
  var hidEl = document.getElementById(hid);
  if (!isElementVisible(hidEl)) {
    hidEl.scrollIntoView();
  }

  // If it has been scheduled already, highlight it on the canvas.
  if (psps.scheduled == 1) {
    scrollToTimestamp(psps.scheduled_start);
    highlightBlock(psp, slotnumber);
  }
  
};

const slotSelectorGen = function(sn) {
  return function() {
    selectSlot(sn);
  };
};

const arraySelectorGen = function(ident, slotnum, tdid) {
  // We call a function to display a dropdown box.
  return function() {
    // Get the list of configurations.
    var arrs = Object.keys(configDescriptor[obs]);
    arrs.sort(function(a, b) {
      return (configDescriptor[obs][a][0] - configDescriptor[obs][b][0]);
    });
    arrs = arrs.map(function(v) {
      return v.toUpperCase();
    });
    // These are our options.
    slotChangeDisplay(tdid, arrs, {
      'callback': slotChangeFulfillment,
      'payload': { 'ident': ident, 'slotnum': slotnum,
		   'type': "array" }
    }, "select");
  };
};

const cabbSelectorGen = function(ident, slotnum, tdid) {
  // We call a function to display a dropdown box.
  return function() {
    var cabbModes = [ "CFB1M", "CFB1M-0.5k", "CFB64M-32k",
		      "CFB1-64M", "CFB1M-pulsar", "VLBI" ];
    slotChangeDisplay(tdid, cabbModes, {
      'callback': slotChangeFulfillment,
      'payload': { 'ident': ident, 'slotnum': slotnum,
		   'type': "bandwidth" }
    }, "select");
  };
};

const backendSelectorGen = function(ident, slotnum, tdid) {
  return function() {
    slotChangeDisplay(tdid, null, {
      'callback': slotChangeFulfillment,
      'payload': { 'ident': ident, 'slotnum': slotnum,
		   'type': "backend" }
    }, "input");
  };
};

const bandsSelectorGen = function(ident, slotnum, tdid) {
  return function() {
    slotChangeDisplay(tdid, null, {
      'callback': slotChangeFulfillment,
      'payload': { 'ident': ident, 'slotnum': slotnum,
		   'type': "band" }
    }, "input");
  };
};

const sourceSelectorGen = function(ident, slotnum, tdid) {
  return function() {
    slotChangeDisplay(tdid, null, {
      'callback': slotChangeFulfillment,
      'payload': { 'ident': ident, 'slotnum': slotnum,
		   'type': "source" }
    }, "input");
  };
};

const matchTime = function(v) {
  var m = /^(\d+)\s+\/\s+([\d\.]+)$/.exec(v);
  return m[2];
};

const timeSelectorGen = function(ident, slotnum, tdid) {
  return function() {
    slotChangeDisplay(tdid, matchTime,
		      {'callback': slotChangeFulfillment,
		       'payload': { 'ident': ident, 'slotnum': slotnum,
				    'type': "time" }},
		      'input');
  };
};

const slotChangeFulfillment = function(proj, value) {
  var project = getProjectByName(proj.ident);
  var slot = project.details.slot[proj.slotnum];

  // Check if a change has been made.
  var changed = false;
  if (proj.type == "array") {
    var nv = value.toLowerCase();
    if (slot.array != nv) {
      changed = true;
      if (obs == "atca") {
	printMessage("Changed array for " + proj.ident + " slot from " +
		     slot.array.toUpperCase() + " to " +
		     nv.toUpperCase() + ".", "warning");
      } else if (obs == "parkes") {
	var recvString = "";
	if (slot.array instanceof Array) {
	  recvString = slot.array.join("/").toUpperCase();
	} else {
	  recvString = slot.array.toUpperCase();
	}
	printMessage("Changed receiver for " + proj.ident + " slot from " +
		     recvString + " to " + nv.toUpperCase() + ".",
		     "warning");
      }
      slot.array = nv;
    }
  } else if (proj.type == "bandwidth") {
    if (slot.bandwidth != value) {
      changed = true;
      printMessage("Changed bandwidth for " + proj.ident + " slot from " +
		   slot.bandwidth + " to " + value + ".", "warning");
      slot.bandwidth = value;
    }
  } else if (proj.type == "band") {
    // Split up the new string.
    var bands = value.split(",");
    var same = compareStringArrays(bands, slot.bands);
    if (!same) {
      changed = true;
      printMessage("Changed bands for " + proj.ident + " slot from " +
		   slot.bands.join(",") + " to " +
		   bands.join(",") + ".", "warning");
      slot.bands = bands;
    }
  } else if (proj.type == "backend") {
    if (slot.bandwidth != value) {
      changed = true;
      printMessage("Changed backend for " + proj.ident + " slot from " +
		   slot.bandwidth + " to " + value + ".", "warning");
      slot.bandwidth = value;
    }
  } else if (proj.type == "time") {
    var time = parseFloat(value);
    if (time != slot.requested_duration) {
      changed = true;
      printMessage("Changed requested duration for " + proj.ident +
		   " slot from " + slot.requested_duration + " hrs to " +
		   time + " hrs.", "warning");
      slot.requested_duration = time;
    }
  } else if (proj.type == "source") {
    if (value != slot.source) {
      changed = true;
      printMessage("Changed source name for " + proj.ident + " slot from " +
		   slot.source + " to " + value + ".", "warning");
      slot.source = value;
    }
  }

  var bo = findBlockObject(proj, proj.slotnum);
  if (bo != null) {
    // Force this to be remade.
    bo.clean = true;
  }
  
  if (changed) {
    scheduleUpdated();
  }

  showProjectDetails(proj.ident);

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

// Add a change handler for a DOM element.
const addChangeHandler = function(e, callback) {
  if (e) {
    e.addEventListener("change", callback);
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

const addDoubleClickHandler = function(e, callback) {
  if (e) {
    e.addEventListener("dblclick", callback);
    // Add the class to show it can be clicked.
    domAddClasses(e, "clickEnabled");
  }
};

// Make the project table.
const updateProjectTable = function() {
  // Have we already made the table?
  var t = document.getElementById("projects-table");
  // Go through the projects.
  allProjectSummary = summariseProjects();
  // Sort the projects by rank.
  var sortedProjects = allProjectSummary;
  sortedProjects.sort(function(a, b) {
    return (b.rating - a.rating);
  });

  if (!t) {
    // Not made yet.
    // Make it.
    t = makeElement("table", null, { 'id': "projects-table" });
    var d = document.getElementById("projecttable");
    d.appendChild(t);
    var h = makeElement("tr");
    var th = makeElement("th", "Project", { 'rowspan': 2 });
    h.appendChild(th);
    th = makeElement("th", "Rank", { 'rowspan': 2 });
    h.appendChild(th);
    th = makeElement("th", "Time (h)", { 'colspan': 2 });
    h.appendChild(th);
    th = makeElement("th", "Slots", { 'colspan': 2 });
    h.appendChild(th);
    t.appendChild(h);
    h = makeElement("tr");
    th = makeElement("th", "Sched");
    h.appendChild(th);
    th = makeElement("th", "Req");
    h.appendChild(th);
    th = makeElement("th", "Sched");
    h.appendChild(th);
    th = makeElement("th", "Req");
    h.appendChild(th);
    t.appendChild(h);

    
    for (var i = 0; i < sortedProjects.length; i++) {
      var p = sortedProjects[i];
      var r = makeElement("tr", null, { 'id': "row-" + p.ident });
      t.appendChild(r);
      tableRows[p.ident] = r;
      // The name element never changes.
      var td = makeElement("td", p.ident, { 'id': "identcell-" + p.ident });
      // Check if this has a colour associated.
      if (p.hasOwnProperty("colour")) {
	var st = document.createAttribute("style");
	st.value = "background-color: #" + p.colour;
	td.setAttributeNode(st);
      }
      r.appendChild(td);
      // Is it a NAPA?
      if (p.isNapa) {
	fillId("identcell-" + p.ident, null, "napaTitle");
      }
      // We put an event handler on this to show its details.
      addClickHandler(td, projectClicker(p.ident));
      // The rating element never changes.
      td = makeElement("td", p.rating);
      r.appendChild(td);
      // The scheduled time element will need to be changed.
      td = makeElement("td", "NN", {
	'id': "scheduledTime-" + p.ident });
      r.appendChild(td);
      // The requested time may be changed.
      td = makeElement("td", "NN", {
	'id': "requestedTime-" + p.ident });
      r.appendChild(td);
      // The scheduled slots element will need to be changed.
      td = makeElement("td", "NN", {
	'id': "scheduledSlots-" + p.ident });
      r.appendChild(td);
      // The requested slots can be altered.
      td = makeElement("td", "NN", {
	'id': "requestedSlots-" + p.ident });
      r.appendChild(td);
    }
  }

  // Update the table cells and rows.
  for (var i = 0; i < sortedProjects.length; i++) {
    var p = sortedProjects[i];
    fillId("scheduledTime-" + p.ident, p.scheduledTime);
    fillId("requestedTime-" + p.ident, p.requestedTime);
    fillId("scheduledSlots-" + p.ident, p.scheduledSlots);
    fillId("requestedSlots-" + p.ident, p.requestedSlots);
    var prow = "row-" + p.ident;
    if (p.scheduledTime >= p.requestedTime) {
      fillId(prow, null, "completelyScheduled", "partiallyScheduled");
    } else if (p.scheduledTime > 0) {
      fillId(prow, null, "partiallyScheduled", "completelyScheduled");
    } else {
      fillId(prow, null, null,
	     [ "partiallyScheduled", "completelyScheduled" ]);
    }
  }
  
};

// Another helper function.
const makeTableCell = function(type, text, parent, attr) {
  var e = makeElement(type, text, attr);
  parent.appendChild(e);
  return e;
};

var savedDomNodes = {};

// Display the status of the entire semester.
const updateSemesterSummary = function() {
  // Get our helper to make the summary.
  var semsum = summariseSemester();
  console.log(semsum);
  
  // Step 1: show the demand for each array type.
  // Have we already made the table?
  var arrayTable = document.getElementById("array-demand-table");
  if (!arrayTable) {
    // Not made yet, so we make it.
    var ss = document.getElementById("semestersummary");
    arrayTable = makeElement("table", null, { 'id': "array-demand-table" });
    ss.appendChild(arrayTable);
    var r = makeElement("tr");
    arrayTable.appendChild(r);
    var th = makeElement("th", "Score", { 'colspan': 3 });
    r.appendChild(th);
    th = makeElement("th", "Time Requested (days)", {
      'colspan': semsum.arrayLabels.length });
    r.appendChild(th);
    r = makeElement("tr");
    arrayTable.appendChild(r);
    th = makeElement("th", "%");
    r.appendChild(th);
    th = makeElement("th", "Score");
    r.appendChild(th);
    th = makeElement("th", "Days");
    r.appendChild(th);
    var showLabels = {};
    for (var i = 0; i < semsum.arrayLabels.length; i++) {
      var label = "";
      var tm = semsum.arrays[0];
      for (var k in semsum.arrayLabels[i]) {
	if (semsum.arrayLabels[i].hasOwnProperty(k)) {
	  tm = tm[k];
	  if (obs == "atca") {
	    for (var l in semsum.arrayLabels[i][k]) {
	      if (semsum.arrayLabels[i][k].hasOwnProperty(l)) {
		tm = tm[l]
		label = semsum.arrayLabels[i][k][l];
	      }
	    }
	  } else if (obs == "parkes") {
	    label = semsum.arrayLabels[i][k];
	  }
	}
      }
      if (tm > 0) {
	th = makeElement("th", label);
	r.appendChild(th);
	showLabels[label] = true;
      }
    }

    // Show the following fractions of the semester.
    var semFractions = [ 0.5, 0.7, 0.8 ];
    var scoreFractions = [ null, null, null ];
    var scoreDays = [ 0, 0, 0 ];
    for (var i = (semsum.arrays.length - 1); i >= 0; i--) {
      // Compute the total.
      var totalTime = 0;
      for (var arr in semsum.arrays[i]) {
	if ((semsum.arrays[i].hasOwnProperty(arr)) &&
	    (arr != "score")) {
	  if (obs == "atca") {
	    for (var atype in semsum.arrays[i][arr]) {
	      if (semsum.arrays[i][arr].hasOwnProperty(atype)) {
		totalTime += semsum.arrays[i][arr][atype];
	      }
	    }
	  } else if (obs == "parkes") {
	    totalTime += semsum.arrays[i][arr];
	  }
	}
      }
      // Compute the fraction.
      var fracTime = totalTime / semsum.timeSummary.available;
      for (var j = 0; j < semFractions.length; j++) {
	if (fracTime <= semFractions[j]) {
	  scoreFractions[j] = semsum.arrays[i];
	  scoreDays[j] = Math.ceil(totalTime / 24.0);
	}
      }
    }

    for (var i = 0; i < semFractions.length; i++) {
      r = makeElement("tr");
      arrayTable.appendChild(r);
      th = makeElement("th", Math.floor(semFractions[i] * 100));
      r.appendChild(th);
      th = makeElement("th", scoreFractions[i].score);
      r.appendChild(th);
      th = makeElement("th", scoreDays[i]);
      r.appendChild(th);
      for (var j = 0; j < semsum.arrayLabels.length; j++) {
	var tm = scoreFractions[i];
	var tlab = "";
	for (var k in semsum.arrayLabels[j]) {
	  if (semsum.arrayLabels[j].hasOwnProperty(k)) {
	    tm = tm[k];
	    if (obs == "atca") {
	      for (var l in semsum.arrayLabels[j][k]) {
		if (semsum.arrayLabels[j][k].hasOwnProperty(l)) {
		  tm = tm[l];
		  tlab = semsum.arrayLabels[j][k][l];
		}
	      }
	    } else if (obs == "parkes") {
	      tlab = semsum.arrayLabels[j][k];
	    }
	  }
	}
	var nd = Math.ceil(tm / 24.0);
	if (showLabels[tlab]) {
	  var td = makeElement("td", nd);
	  r.appendChild(td);
	}
      }
    }
  }

  // Step 2: show the current state.
  // Have we already made the table?
  var stateTable = document.getElementById("semester-state-table");
  if (!stateTable) {
    // Not made yet, so we make it.
    var semesterStateTable = makeElement("table", null, {
      'id': "semester-state-table" });
    var th, td;
    var ss = document.getElementById("semestersummary");
    ss.appendChild(semesterStateTable);
    var r = makeElement("tr");
    semesterStateTable.appendChild(r);
    makeTableCell("th", "Available (h):", r);
    savedDomNodes.availableTime = makeTableCell("td", "NN", r, {
      'id': "sst-available-time" });
    makeTableCell("th", "Scheduled (h):", r);
    savedDomNodes.scheduledTime = makeTableCell("td", "NN", r, {
      'id': "sst-scheduled-time" });
    makeTableCell("th", "Remaining (h):", r);
    savedDomNodes.remainingTime = makeTableCell("td", "NN", r, {
      'id': "sst-remaining-time" });
    r = makeElement("tr");
    semesterStateTable.appendChild(r);
    makeTableCell("th", "Calibration:", r);
    savedDomNodes.calibrationTime = makeTableCell("td", "NN", r, {
      'id': "sst-calibration-allocation" });
    if (obs == "atca") {
      makeTableCell("th", "Legacy:", r);
      savedDomNodes.legacyTime = makeTableCell("td", "NN", r, {
	'id': "sst-legacy-allocation" });
    } else if (obs == "parkes") {
      makeTableCell("th", "Funded:", r);
      savedDomNodes.fundedTime = makeTableCell("td", "NN", r, {
	'id': "sst-funded-allocation" });
    }
    makeTableCell("th", "VLBI:", r);
    savedDomNodes.vlbiTime = makeTableCell("td", "NN", r, {
      'id': "sst-vlbi-allocation" });
    r = makeElement("tr");
    semesterStateTable.appendChild(r);
    makeTableCell("th", "Maintenance:", r);
    savedDomNodes.maintenanceTime = makeTableCell("td", "NN", r, {
      'id': "sst-maintenance-allocation" });
    makeTableCell("th", "Reconfigs:", r);
    savedDomNodes.reconfigTime = makeTableCell("td", "NN", r, {
      'id': "sst-reconfig-allocation" });
    if (obs == "atca") {
      makeTableCell("th", "CABB:", r);
      savedDomNodes.cabbTime = makeTableCell("td", "NN", r, {
	'id': "sst-cabb-allocation" });
    }
    
  }

  // Update the table.
  if (obs == "atca") {
    savedDomNodes.availableTime.innerHTML =
      semsum.timeSummary.available - semsum.timeSummary.scheduled -
      semsum.timeSummary.calibration - semsum.timeSummary.legacy -
      semsum.timeSummary.vlbi - semsum.timeSummary.maintenance;
    savedDomNodes.legacyTime.innerHTML = semsum.timeSummary.legacy;
    savedDomNodes.cabbTime.innerHTML = semsum.timeSummary.nCabb;
  } else if (obs == "parkes") {
    savedDomNodes.availableTime.innerHTML =
      semsum.timeSummary.available - semsum.timeSummary.scheduled -
      semsum.timeSummary.calibration - semsum.timeSummary.funded -
      semsum.timeSummary.vlbi - semsum.timeSummary.maintenance;
    savedDomNodes.fundedTime.innerHTML = semsum.timeSummary.funded;
  }
  savedDomNodes.scheduledTime.innerHTML = semsum.timeSummary.scheduled;
  savedDomNodes.remainingTime.innerHTML = (semsum.timeSummary.requested -
					   semsum.timeSummary.scheduled);
  savedDomNodes.calibrationTime.innerHTML = semsum.timeSummary.calibration;
  savedDomNodes.vlbiTime.innerHTML = semsum.timeSummary.vlbi;
  savedDomNodes.maintenanceTime.innerHTML = semsum.timeSummary.maintenance;
  savedDomNodes.reconfigTime.innerHTML = semsum.timeSummary.nReconfigure;

};


// This function takes a pointer position on the canvas and returns
// the day number, and hour down to 0.5 precision.
const pointerTime = function(e) {
  var pp = stage.getPointerPosition();
  return posTime(pp.x, pp.y);
};

const posTime = function(x, y) {

  // The day can be gotten from the y location.
  var nDays = Math.floor((y - meas.marginTop) / meas.dayHeight);

  // The hour can be gotten from the x location.
  var nHalfHours = Math.floor((x - (meas.marginLeft + meas.dayLabelWidth)) /
			      meas.halfHourWidth);
  if (nHalfHours < 0) {
    nHalfHours = 0;
  } else if (nHalfHours >= 47) {
    nHalfHours = 47;
  }

  // Get the time stamp here.
  var epoch = (allDates[nDays].getTime() / 1000) +
      (nHalfHours * 1800);
  
  return { 'day': nDays, 'hour': (nHalfHours / 2), 'timestamp': epoch };

};


// This routine should be called when a project slot is to be
// scheduled, given an indicative time (day of sched and time).
// It works out if the slot can be scheduled within some tolerance,
// and if so, puts it in at the optimal position given the constraints.
// Setting force to true will ensure that the start time is assumed correct,
// regardless of restrictions. Specifying the duration number (in hours)
// will over-ride the requested_duration number in the schedule (but
// will not change the requested_duration).
const scheduleInsert = function(ident, slotNumber, time, force, duration) {
  // Get the project.
  var proj = getProjectByName(ident);

  if (proj.details == null) {
    printMessage("Did not find the project to schedule!", "error");
    console.log("something has gone terribly wrong");
    return null;
  }

  // Get the slot.
  var slot = proj.details.slot[slotNumber];
  if (typeof slot == "undefined") {
    printMessage("Did not find the slot to schedule!", "error");
    console.log("nothing is going right");
    return null;
  }

  // Get the actual date for the day number.
  var d = allDates[time.day];
  // Check if this is on the excluded days list.
  var excluded = false;
  if (proj.details.excluded_dates instanceof Array) {
    for (var i = 0; i < proj.details.excluded_dates.length; i++) {
      var cd = new Date(proj.details.excluded_dates[i] * 1000);
      var dcr = compareDates(d, cd);
      if (dcr == 0) {
	excluded = true;
	break;
      }
    }
  }
  // Check for weekends for certain projects.
  if ((ident == "MAINT") || (ident == "CONFIG")) {
    if ((d.getDay() == 0) || (d.getDay() == 6)) {
      excluded = true;
    }
  }
  if ((excluded) && (!force)) {
    printMessage("Attempted to schedule " + ident +
		 " on an unsuitable date.", "error");
    return null;
  }

  // Check if the array configuration is suitable.
  var arrayConfigured = whichArrayConfiguration(time.day);
  var compatible = arrayCompatible(arrayConfigured, slot.array);
  if ((!compatible) && (ident != "CONFIG")) {
    printMessage("Attempted to schedule a " + proj.details.ident +
		 " slot requiring " + slot.array.toUpperCase() + ", but configuration " +
		 "on selected date is not compatible (" +
		 arrayConfigured +").", "error");
    return null;
  }

  // Work out when we should start on this day.
  var hStart = null;
  var startingDate = null;
  if (force) {
    startingDate = new Date(time.timestamp * 1000);
    // Check we haven't moved outside the semester boundaries.
    if (startingDate < semesterStart) {
      return null;
    }
  } else if ((ident == "MAINT") || (ident == "CONFIG")) {
    // This is a maintenance block, and we try to start at 8am
    // local on the day that was clicked. This doesn't
    // necessarily mean 8am AEST, given daylight savings.
    startingDate = new Date(d.getTime());
    startingDate.setHours(8);
    startingDate.setMinutes(0);
    startingDate.setSeconds(0);
    hStart = startingDate.getUTCHours();
  } else if ((ident == "CABB") || (ident == "VLBI")) {
    // We just put this down where the user clicked.
    startingDate = new Date(time.timestamp * 1000);
  } else {
    // A normal project, we have to be guided by LST.
    var sidres = calculateSiderealRestrictions(
      slot.position.ra, slot.position.dec, d);
    // The zenith time minus half the slot length should be ideal.
    var startHour = hourBounds(sidres.zenith - (slot.requested_duration / 2));
    var decDeg = stringToDegrees(slot.position.dec);
    if ((sidres.alwaysUp) && (Math.abs(decDeg + 90) < 0.001)) {
      // This probably means the project doesn't have a target.
      // We now use the time that was clicked.
      startHour = time.hour;
    }
    // Round it to the nearest half hour.
    startHour = Math.round(2 * startHour) / 2;
    // Work out if it's closer to go back or forwards.
    if ((Math.abs(startHour - time.hour) > (slot.requested_duration / 2)) &&
	(startHour < time.hour)) {
      // We've wrapped days.
      d = allDates[time.day + 1];
    }
    startingDate = new Date(d.getTime() + startHour * 3600000);
  }
  if (startingDate == null) {
    printMessage("Unable to find a suitable time to start " +
		 ident + " slot!", "error");
    return null;
  /*} else {
    console.log(startingDate); */
  }

  // Check if something else is already scheduled at this time.
  var overlap = scheduledAt(startingDate);

  if (overlap != null) {
    // Determine what we should do. By default, we assume that the
    // more desirable project was scheduled first, and we just start when
    // the slot ends.
    var endDate = endingDate(overlap.project, overlap.slot);
    // Check if we can use this end date.
    if ((ident == "MAINT") || (ident == "CONFIG")) {
      // We need to start within office hours.
      if ((!force) && ((endDate.getHours() > 15) || (endDate.getHours() <= 8))) {
	// This won't work.
	printMessage("Unable to schedule " + ident +" block, as it would " +
		     "fall out of office hours.", "error");
	return null;
      } else {
	startingDate = endDate;
      }
    } else {
      startingDate = endDate;
    }
  /*} else {
    console.log("no overlapping project found"); */
  }

  // If we reach here we have a usable start date.
  // Now we determine the duration.
  var dur = slot.requested_duration;
  if (slot.scheduled_duration > 0) {
    dur = slot.scheduled_duration;
  }
  if ((typeof duration != "undefined") &&
      (duration > 0)) {
    dur = duration;
  }
  dur *= 3600000;
  var endDate = new Date(startingDate.getTime() + dur);
  // Check for a conflicting project.
  var conflicts = scheduledBetween(startingDate, endDate);
  if (conflicts.length > 0) {
    endDate = getEarliestDate(conflicts);
  }
  if (endDate < startingDate) {
    // We've tried to start within a project; shouldn't have happened.
    printMessage("An unexpected error occured while attempting to " +
		 "schedule " + ident + " slot.", "error");
    console.log("we got trapped somehow, aborting");
    return null;
  }
  // Deal with ending dates outside acceptable ranges.
  if (!force) {
    if (ident == "MAINT") {
      // We want to end at or before 4pm local time.
      if ((endDate.getHours() > 16) ||
	  (endDate.getHours() < 8)) {
	if (endDate.getHours() < 8) {
	  // We also go back a day.
	  endDate.setTime(endDate.getTime() - 86400000);
	}
	endDate.setHours(16);
	endDate.setMinutes(0);
	endDate.setSeconds(0);
      }
    } else if (ident == "CONFIG") {
      // We want to end at or before 8am the next day.
      if ((endDate.getHours() > 8) &&
	  ((endDate.getTime() - startingDate.getTime()) > (12 * 3600000))) {
	endDate.setHours(8);
	endDate.setMinutes(0);
	endDate.setSeconds(0);
      }
    }
  }

  // If we get here, we're good to put this in the schedule.
  //console.log("scheduling the slot");
  slot.scheduled_start = startingDate.getTime() / 1000;
  slot.scheduled_duration = (endDate.getTime() - startingDate.getTime()) / 3600000;
  slot.scheduled = 1;
  printMessage("Scheduled " + ident + " slot for " +
	       slot.scheduled_duration + " hours starting at " +
	       datetimeToString(startingDate) + ".");

  // Redraw everything.
  scheduleUpdated();

  return slot;
};

const handleCanvasClick = function(e) {
  // Get the time and day that was clicked.
  var timeClicked = pointerTime(e);
  
  // Check if there is a block scheduled where the click was.
  var scheduled = scheduledAt(timeClicked.timestamp);
  if (scheduled != null) {
    if ((previouslySelectedProject == null) ||
	(previouslySelectedProject.details.ident != scheduled.project.ident)) {
      showProjectDetails(scheduled.project.ident);
    }
    selectSlot(scheduled.slot);
  }
  
  // Has a project and slot been selected?
  if ((previouslySelectedProject != null) &&
      (previouslySelectedSlot != null)) {
    // Has this project already been scheduled?
    if (previouslySelectedProject.details.slot[previouslySelectedSlot]
	.scheduled == 0) {
      // It looks like the user wants to schedule this project.
      scheduleInsert(previouslySelectedProject.details.ident,
		     previouslySelectedSlot,
		     timeClicked);
    }
  }
};


// Find a project by name.
const getProjectByName = function(name) {
  if (scheduleData == null) {
    return;
  }
  
  var allProjects = scheduleData.program.project;

  var r = { 'details': null, 'summary': null };
  for (var i = 0; i < allProjects.length; i++) {
    if (name == allProjects[i].ident) {
      r.details = allProjects[i];
    }
  }
  if (allProjectSummary != null) {
    for (var i = 0; i < allProjectSummary.length; i++) {
      if (name == allProjectSummary[i].ident) {
	r.summary = allProjectSummary[i];
      }
    }
  }

  return r;
};

const projectClicker = function(ident) {
  return function() {
    showProjectDetails(ident);
  };
};




// Work out which array configuration is currently scheduled at
// some particular day d, which is the day of the schedule.
const whichArrayConfiguration = function(d) {
  var configs = getProjectByName("CONFIG");
  var slots = configs.details.slot;

  var configBefore = slots[0].array;
  var dtime = allDates[d].getTime() / 1000;
  var mindiff = dtime - slots[0].scheduled_start;
  for (var i = 1; i < slots.length; i++) {
    var cdiff = dtime - slots[i].scheduled_start;
    if (cdiff < 0) {
      // This is afterwards.
      continue;
    }
    if (cdiff < mindiff) {
      mindiff = cdiff;
      configBefore = slots[i].array;
    }
  }

  return configBefore;
};

// Determine if the array configuration config is compatible with
// the array required.
const arrayCompatible = function(config, required) {
  var lconfig = config.toLowerCase();
  var lrequired = required.toLowerCase();
  if (configDescriptor[obs].hasOwnProperty(lconfig)) {
    if (configDescriptor[obs][lconfig].indexOf(lrequired) >= 0) {
      return true;
    /*} else {
      console.log(lrequired + " not compatible with " + lconfig);*/
    }
  /*} else {
    console.log("Config " + lconfig + " not found!");*/
  }
  return false;
};

// Draw the status of the array configurations.
const drawArrayConfigurations = function() {
  // Go through the array configurations in the data and work out
  // how the boxes should look on the right side.
  // Get the list of configurations.
  var configs = getProjectByName("CONFIG");
  var slots = configs.details.slot;

  // Destroy all the current children.
  arrayGroup.destroyChildren();
  
  // Check if the first slot has a start time.
  if (slots[0].scheduled_start == 0) {
    // This is the first array, so we assume it is from
    // the start of the semester.
    slots[0].scheduled_start = scheduleFirst.getTime() / 1000;
  }

  var currentConfig = 0;
  // Go through all the configs until we find the next one.
  while (true) {
    var nextConfig = -1;
    var minDiff = 365 * 86400 * 1000;
    for (var i = 0; i < slots.length; i++) {
      if (i == currentConfig) {
	continue;
      }
      if (slots[i].scheduled == 0) {
	continue;
      }
      var tdiff = slots[i].scheduled_start - slots[currentConfig].scheduled_start;
      if ((tdiff > 0) && (tdiff < minDiff)) {
	minDiff = tdiff;
	nextConfig = i;
      }
    }

    if (nextConfig == -1) {
      // We've reached the end of the configurations.
      break;
    }

    drawConfiguration(slots[currentConfig].array,
		      slots[currentConfig].scheduled_start,
		      slots[nextConfig].scheduled_start);
    currentConfig = nextConfig;
  }

  // Draw the last configuration.
  drawConfiguration(slots[currentConfig].array,
		    slots[currentConfig].scheduled_start,
		    (scheduleLast.getTime() / 1000));

  arrayLayer.draw();
};

// Clear the part of the page which shows the available slots.
const clearSlotSelector = function() {
  fillId("projectselectedIdent", "NONE");
  fillId("projectselectedPI", "NOBODY");
  fillId("projectselectedTitle", "NOTHING");
  var projectselectedTable = document.getElementById("projectselected");
  projectselectedTable.style["background-color"] = "white";

  emptyDomNode("projectslotsSelectionBody");

  // Deselect the slots.
  if (previouslySelectedSlot != null) {
    var hid = "slotrow-" + previouslySelectedProject.details.ident +
	"-" + previouslySelectedSlot;
    fillId(hid, null, null, "slotSelected");
    previouslySelectedSlot = null;
  }

  // Clear the inputs.
  fillId("projectcomments", "");
  var nc = document.getElementById("nighttime");
  nc.checked = false;
  
  fillInput("gooddates", "");
  fillInput("baddates", "");
  
};

// The page initialisation function.
const pageInit = function(status, data) {
  if ((typeof data == "undefined") || (data == null)) {
    printMessage("Did not receive data from the local storage or the " +
		 "server. Unable to proceed!", "error");
    console.log("Unable to retrieve data.");
    return;
  }

  // Keep the data for later.
  console.log(data);
  scheduleData = data;

  // Save the telescope and semester names.
  obs = scheduleData.program.observatory.observatory;
  setObservatory(obs);
  semester = scheduleData.program.term.term;
  setSemester(semester);
  
  // Save the data locally.
  saveLocalSchedule();
  // Display some times.
  checkLocalTime(displayModificationTimes);

  // Display the schedule version.
  fillInput("scheduleVersion", scheduleData.program.term.version);
  
  // Work out the semester time details.
  semesterStart = new Date(scheduleData.program.term.start);
  semesterEnd = new Date(scheduleData.program.term.end);
  
  setupCanvas(scheduleData);
  updateProjectTable();
  updateSemesterSummary();

  // Remove any displayed project.
  clearSlotSelector();
  previouslySelectedProject = null;
}

// Show the online or offline state.
const showLineState = function() {
  var indicator = document.getElementById("onlineState");
  if (navigator.onLine) {
    indicator.innerHTML = "ONLINE";
    return "ONLINE";
  } else {
    indicator.innerHTML = "OFFLINE";
    return "OFFLINE";
  }
};

// Check what the server schedule modification time is.
const checkServerTime = function(callback) {
  if (navigator.onLine) {
    // We need to be online of course.
    var xhr = new XMLHttpRequest();
    var gstring = "?request=loadtime&observatory=" + obs;
    if (semester != null) {
      gstring += "&term=" + semester;
    }
    xhr.open('GET', spath + gstring, true);
    xhr.responseType = "json";
    xhr.onload = function() {
      var status = xhr.status;
      if (status === 200) {
	serverModificationTime = xhr.response.modificationTime;
	if (typeof callback != "undefined") {
	  callback();
	}
      } else {
	console.log("cannot get server modification time");
      }
    };
    xhr.send();
  }
};

const getTimeString = function(dateObject) {
  var dstring = dateObject.toISOString();
  return dstring.substring(0, 19).replace("T", " ");
};

const displayModificationTimes = function() {
  if (serverModificationTime != null) {
    var stime = document.getElementById("serverSaveTime");
    var sdate = new Date(serverModificationTime * 1000);
    stime.innerHTML = getTimeString(sdate);
  }
  if (localModificationTime != null) {
    var stime = document.getElementById("localSaveTime");
    var sdate = new Date(localModificationTime * 1000);
    stime.innerHTML = getTimeString(sdate);
  }
};


const getLocalSchedule = function() {
  // Try to get the schedule from our local storage.
  if ((obs == null) || (semester == null)) {
    // We haven't saved anything yet if this is the case.
    return null;
  }
  var keyName = localKey + "-" + obs + "-" + semester;
  var localSchedule = window.localStorage.getItem(keyName);
  if ((typeof localSchedule != "undefined") &&
      (localSchedule != "undefined")) {
    return JSON.parse(localSchedule);
  }
  return null;
};

const updateLocalSchedule = function() {
  // This routine uses the save function, but updates the modification
  // time beforehand.
  if (scheduleData != null) {
    var n = new Date();
    scheduleData.modificationTime = n.getTime() / 1000;
  }
  saveLocalSchedule();
};

const saveLocalSchedule = function() {
  if (scheduleData != null) {
    localModificationTime = scheduleData.modificationTime;
    var keyName = localKey + "-" + obs + "-" + semester;
    window.localStorage.setItem(keyName, JSON.stringify(scheduleData));
  }
  displayModificationTimes();
};

const saveScheduleToServer = function() {
  if (scheduleData != null) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", spath, true)
    xhr.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
    xhr.responseType = "json";
    xhr.onload = function() {
      var status = xhr.status;
      if (status === 200) {
	printMessage("Schedule saved to the server.");
	displayModificationTimes();
      } else {
	printMessage("Failed to save schedule to the server.",
		     "error");
	displayModificationTimes();
      }
    }
    //xhr.send({ "request": "save",
    //	       "schedule": JSON.stringify(scheduleData) });
    var sstring = "request=save&observatory=" + obs +
	"&term=" + semester + "&schedule=" + JSON.stringify(scheduleData);
    xhr.send(sstring);
  }
};

const closeModalMessage = function() {
  var m = document.getElementById("myModal");
  m.style.display = "none";
};

const displayModalMessage = function(msg, showOptions, closeHandlers) {
  var m = document.getElementById("myModal");
  if (typeof msg != "undefined") {
    fillId("modalBodyText", msg);

    // Determine which options to show.
    var c = document.getElementById("modalcloser");
    var y = document.getElementById("modalyes");
    var n = document.getElementById("modalno");
    if (showOptions == false) {
      // We display just the closing mark.
      c.style.display = "inline-block";
      y.style.display = "none";
      n.style.display = "none";
      if ((typeof closeHandlers != "undefined") &&
	  (typeof closeHandlers.close != "undefined")) {
	addClickHandler(c, closeHandlers.close);
      } else {
	// Generic close handler.
	addClickHandler(c, closeModalMessage);
      }
    } else {
      // We display the yes/no options.
      c.style.display = "none";
      y.style.display = "inline-block";
      n.style.display = "inline-block";
      var yHandler = closeModalMessage;
      var nHandler = closeModalMessage;
      if (typeof closeHandlers != "undefined") {
	if (typeof closeHandlers.yes != "undefined") {
	  yHandler = closeHandlers.yes;
	}
	if (typeof closeHandlers.no != "undefined") {
	  nHandler = closeHandlers.no;
	}
      }
      addClickHandler(y, yHandler);
      addClickHandler(n, nHandler);
    }
    // Show the modal.
    m.style.display = "block";
  }
  
};

const revertScheduleToServer = function() {
  // Close the modal.
  closeModalMessage();

  // Load the schedule.
  loadFile(pageInit, true);
  
  // Tell the user what has happened.
  displayModalMessage("Schedule reverted to server version.", false);
  printMessage("Schedule reverted to server version.", "warning");
};

const revertCancel = function() {
  // Close the modal.
  closeModalMessage();

  // Tell the user we didn't revert.
  displayModalMessage("Revert cancelled.", false);
  
};

const revertScheduleToServerCheck = function() {
  // We don't do anything unless the server date is earlier
  // than the local modification date.
  if (!navigator.onLine) {
    // Can't revert, we're not online.
    displayModalMessage("Not online, cannot revert.");
  } else  if (localModificationTime <= serverModificationTime) {
    displayModalMessage("The local schedule is the same as the server, no need to revert.", false);
  } else {
    displayModalMessage("WARNING: reverting the schedule will lose all changes. Are you sure?",
			true, { 'yes': revertScheduleToServer,
				'no': revertCancel });
  }
};

const checkLocalTime = function(callback) {
  // See if we have a local schedule.
  var localSchedule = getLocalSchedule();
  if (localSchedule != null) {
    localModificationTime = localSchedule.modificationTime;
  }
  localChecked = true;
  if (typeof callback != "undefined") {
    callback();
  }
};

showLineState();

// Our event handler for when the nighttime checkbox changes state.
const nighttimeChange = function() {
  var nc = document.getElementById("nighttime");
  // Are we actually looking at a project now?
  if (previouslySelectedProject == null) {
    // Nope. Set the checkbox back to unchecked.
    nc.checked = false;
    return;
  }

  // Get the current state.
  var cs = nc.checked;
  // Set this in the project details.
  previouslySelectedProject.details.prefers_night = (nc.checked) ? 1 : 0;
  // Save the change locally.
  updateLocalSchedule();
};

// Our event handler for when one of the date boxes gets changed.
const dateChange = function(type) {
  var db = null;
  if (type == "good") {
    db = document.getElementById("gooddates");
  } else if (type == "bad") {
    db = document.getElementById("baddates");
  } else {
    return;
  }

  if (previouslySelectedProject == null) {
    // Reset the box.
    if (type == "good") {
      fillInput("gooddates", "");
    } else if (type == "bad") {
      fillInput("baddates", "");
    }
    return;
  }

  var dates = convertSmallDates(db.value);
  if (type == "good") {
    previouslySelectedProject.details.preferred_dates = dates;
  } else if (type == "bad") {
    previouslySelectedProject.details.excluded_dates = dates;
  }

  updateLocalSchedule();
};

// This routine makes a new slot object that is identical to
// the one passed to it as s.
const duplicateSlot = function(s) {
  if (typeof s == "undefined") {
    return;
  }

  var sString = JSON.stringify(s);
  var r = JSON.parse(sString);
  // Remove any scheduled time from the duplicated object.
  r.scheduled = 0;
  r.scheduled_duration = 0;
  r.scheduled_start = 0;
  return r;
};

// Our event handler for when the copy slot button gets clicked.
const copySlot = function() {
  // Is anything selected?
  if ((previouslySelectedProject == null) ||
      (previouslySelectedSlot == null)) {
    return;
  }

  // Copy the currently selected slot and add it to the end
  // of the slot list.
  previouslySelectedProject.details.slot.push(
    duplicateSlot(previouslySelectedProject.details.slot[previouslySelectedSlot])
  );

  printMessage("Duplicated slot for " +
	       previouslySelectedProject.details.ident + ".");
  
  // Update the table.
  showProjectDetails(previouslySelectedProject.details.ident);
  selectSlot(previouslySelectedProject.details.slot.length - 1);
  updateProjectTable();

  // Save the local schedule.
  updateLocalSchedule();
};

// Our event handler for when the unschedule slot button gets
// clicked.
const unscheduleSlot = function() {
  // Check if it is actually scheduled.
  if ((previouslySelectedProject == null) ||
      (previouslySelectedSlot == null)) {
    return;
  }

  if (previouslySelectedProject.details
      .slot[previouslySelectedSlot].scheduled == 0) {
    return;
  }

  // Otherwise, remove it from the schedule.
  dehighlightBlock(previouslySelectedProject.details,
		   previouslySelectedSlot);
  undrawBlock(previouslySelectedProject.details, previouslySelectedSlot);
  previouslySelectedProject.details.slot[previouslySelectedSlot]
    .scheduled = 0;
  previouslySelectedProject.details.slot[previouslySelectedSlot]
    .scheduled_duration = 0;
  var od = new Date(previouslySelectedProject.details
		    .slot[previouslySelectedSlot].scheduled_start * 1000);
  previouslySelectedProject.details.slot[previouslySelectedSlot]
    .scheduled_start = 0;

  printMessage("Removed " + previouslySelectedProject.details.ident +
	       " slot starting at " + datetimeToString(od) + " from the " +
	       "schedule.", "warning");
  
  // Update the page.
  scheduleUpdated();
  
  
};

// The routine which actually handles a slot deletion.
const deleteThatSlot = function() {
  closeModalMessage();
  
  previouslySelectedProject.details.slot.splice(
    previouslySelectedSlot, 1);

  printMessage("Deleted slot from " +
	       previouslySelectedProject.details.ident + ".", "warning");
  
  // Update all the page details.
  previouslySelectedSlot = null;
  showProjectDetails(previouslySelectedProject.details.ident);
  updateProjectTable();

  // Save the local schedule.
  updateLocalSchedule();
};

// Or if the delete is cancelled.
const deleteCancelled = function() {
  closeModalMessage();

  displayModalMessage("Delete cancelled.", false);
};

// Our event handler for when the delete slot button gets clicked.
const deleteSlot = function() {
  // Check if something is selected.
  if ((previouslySelectedProject == null) ||
      (previouslySelectedSlot == null)) {
    return;
  }

  // Check if we are deleting the first scheduled configuration.
  if ((previouslySelectedProject.details.ident == "CONFIG") &&
      (previouslySelectedSlot == 0)) {
    // Can't delete this one.
    displayModalMessage("ERROR: Unable to delete first config.", false);
    return;
  }
  // Check if we're trying to delete a scheduled block.
  if (previouslySelectedProject.details.slot[previouslySelectedSlot]
      .scheduled == 1) {
    // Can't delete it before it is unscheduled.
    displayModalMessage("ERROR: Cannot delete a scheduled slot. Please " +
			"unschedule it before deleting it.", false);
    return;
  }
  
  // Double check the user wants this.
  displayModalMessage("Are you sure you want to delete the selected slot?",
		      true, { 'yes': deleteThatSlot, 'no': deleteCancelled });
};

// The initial callback for the drop down and text input event handlers.
const slotChangeEventHandler = function(id, callback, type) {
  var d = document.getElementById(id);
  var _listener = function(ev) {
    // Remove the event handlers from the ID.
    d.removeEventListener("change", _listener);
    d.removeEventListener("blur", _listener);
    var v;
    if (type == "select") {
      // Call the callback with the currently selected value.
      v = d.options[d.selectedIndex].value;
    } else if (type == "input") {
      v = d.value;
    }
    callback.callback(callback.payload, v);
  };

  // Set up the handlers.
  d.addEventListener("change", _listener);
  d.addEventListener("blur", _listener);
};

const slotChangeDisplay = function(id, options, callback, type) {
  // Get the current value.
  var e = document.getElementById(id);
  var cv = e.innerHTML;
  if ((type == "input") && (options != null)) {
    // We've been given a manipulation function.
    cv = options(cv);
  } else if ((obs == "parkes") && (cv.includes(","))) {
    // Split the string up and use the first part.
    var cve = cv.split(",");
    cv = cve[0];
  }
  
  // Remove whatever was there before.
  emptyDomNode(id);
  e.innerHTML = "";

  // Set up the dropdown box.
  var inp = document.createElement(type);
  var selid = id + "-" + type;
  inp.setAttribute("id", selid);
  if (type == "input") {
    inp.setAttribute("type", "text");
    if (callback.payload.type == "backend") {
      inp.setAttribute("size", "30");
    } else {
      inp.setAttribute("size", "10");
    }
    inp.setAttribute("value", cv);
  } else if (type == "select") {
    options.forEach(function(v) {
      var o = document.createElement("option");
      o.setAttribute("value", v);
      if (v == cv) {
	o.setAttribute("selected", "selected");
      }
      o.innerHTML = v;
      inp.appendChild(o);
    });
  }

  // Add it to the element.
  e.appendChild(inp);

  // Set the handlers for change and blue.
  slotChangeEventHandler(selid, callback, type);

};

// Configure some event handlers on existing nodes.
const staticEventHandlers = function() {
  // Enable the check box for nighttimes.
  var nc = document.getElementById("nighttime");
  nc.addEventListener("change", nighttimeChange);

  // Enable the check box and inputs for LST restrictions.
  var ul = document.getElementById("sourceUseLST");
  ul.addEventListener("change", lstRestrictionsChange);
  var riseInp = document.getElementById("sourceLSTRise");
  riseInp.addEventListener("change", lstRestrictionsChange);
  riseInp.addEventListener("blur", lstRestrictionsChange);
  var setInp = document.getElementById("sourceLSTSet");
  setInp.addEventListener("change", lstRestrictionsChange);
  setInp.addEventListener("blur", lstRestrictionsChange);
  
  // Enable the save button.
  var sb = document.getElementById("savebutton");
  addClickHandler(sb, saveScheduleToServer);

  // Enable the revert button.
  var rb = document.getElementById("revertbutton");
  addClickHandler(rb, revertScheduleToServerCheck);

  var gd = document.getElementById("gooddates");
  addChangeHandler(gd, function() {
    dateChange("good");
  });

  var bd = document.getElementById("baddates");
  addChangeHandler(bd, function() {
    dateChange("bad");
  });

  var cs = document.getElementById("copyslotbutton");
  addClickHandler(cs, copySlot);

  var us = document.getElementById("unscheduleslotbutton");
  addClickHandler(us, unscheduleSlot);

  var ds = document.getElementById("deleteslotbutton");
  addClickHandler(ds, deleteSlot);

  var vn = document.getElementById("scheduleVersion");
  addChangeHandler(vn, versionChanged);

  var ov = document.getElementById("observatory");
  addChangeHandler(ov, getObservatory);

  var ts = document.getElementById("termSelected");
  addChangeHandler(ts, getSemester);
};
staticEventHandlers();


// Start the process by loading the file.
const pageInitBootstrap = function() {
  return loadFile(pageInit, false);
};

getObservatory();
getSemester();
checkServerTime(pageInitBootstrap);
checkLocalTime(pageInitBootstrap);

const stateChange = function() {
  var s = showLineState();
  printMessage("Now running in " + s + " mode.", "warning");
};
// Set a handler for when the state changes.
window.addEventListener("online", stateChange);
window.addEventListener("offline", stateChange);
