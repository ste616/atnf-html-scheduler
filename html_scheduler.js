/**
 * HTML scheduler for ATCA and Parkes.
 * Jamie Stevens 2019
 */

// Some global variables we need in multiple routines.
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
var allDates = null;

// Function to calculate the DOY.
const doy = function(d) {
  var foy = new Date(d.getFullYear(), 0, 1, 0, 0, 0, 0);
  var td = Math.floor((d.getTime() - foy.getTime()) / (86400 * 1000));
  return (td + 1);
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
  arrayLabelWidth: 60,
  // The height of the hour label part.
  timeLabelHeight: 66
};

// The number of days to display (basically half a leap year, plus a few.
const nDays = (366 / 2) + 4;

// Compute some secondary measurements from the primary measurements.
// The width of an entire day.
meas.dayWidth = 48 * meas.halfHourWidth;
// The canvas width.
meas.width = meas.dayWidth + 3 * meas.marginLeft + meas.elementWidth + meas.dayLabelWidth + meas.arrayLabelWidth;
// The canvas height.
meas.height = nDays * meas.dayHeight + 2 * meas.marginTop;

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
      dayLabelOpts.fill = "#fa8072";
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
      //fillColour = "#00aa00";
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

// Given any number, put it between 0 and 1.
const turnFraction = function(f) {
  return numberBounds(f, 1);
};

const degreesBounds = function(d) {
  return numberBounds(d, 360);
};

const hourBounds = function(h) {
  return numberBounds(h, 24);
};

// Calculate the sidereal time at Greenwich, given an MJD.
const gst = function(mjd, dUT1) {
  var a = 101.0 + 24110.54581 / 86400.0;
  var b = 8640184.812886 / 86400.0;
  var e = 0.093104 / 86400.0;
  var d = 0.0000062 / 86400.0;
  var tu = (mjd - (2451545.0 - 2400000.5)) / 36525.0;
  var sidtim = turnFraction(a + tu * (b + tu * (e - tu * d)));
  var gmst = turnFraction(sidtim + (mjd - Math.floor(mjd) + dUT1 / 86400.0) * 1.002737909350795);
  return gmst;
};

// Calculate the sidereal time at some longitude on the Earth.
const mjd2lst = function(mjd, longitude, dUT1) {
  var lst = turnFraction(gst(mjd, dUT1) + longitude);
  return lst;
};

// Given some sidereal time at time 0, work out how many real hours
// until some nominated sidereal time.
const hoursUntilLst = function(zlst, dlst) {
  if (dlst < zlst) {
    dlst += 24;
  }

  return ((dlst - zlst) / 1.002737909350795);
};

const smallStringToDatetime = function(smstr) {
  // We take a date/month string and work out the date given
  // our semester constraint.
  var dels = smstr.split("/");
  var year = semesterStart.getFullYear();
  console.log("trying " + year + "-" + parseInt(dels[1] - 1) + "-" +
	      parseInt(dels[0]));
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

const convertSmallDates = function(smdates) {
  // Split the date string.
  var sms = smdates.split(",");
  var darr = sms.map(smallStringToDatetime);
  var rarr = darr.map(function(d) {
    return (d.getTime() / 1000);
  });

  return rarr;
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
  var lambda = L + 1.915 * Math.sin(deg2rad(g)) + 0.020 * Math.sin(2 * deg2rad(g));
  // Sun distance from Earth.
  var R = 1.00014 - 0.01671 * Math.cos(deg2rad(g)) - 0.00014 * Math.cos(2 * deg2rad(g));
  // The obliquity, in degrees.
  // We need the number of centuries since J2000.0.
  var T = (n / (100.0 * 365.2525));
  var epsilon = 23.4392911 - (46.636769 / 3600.0) * T - (0.0001831 / 3600.0) * T * T +
      (0.00200340 / 3600.0) * T * T * T;
  // Get the right ascension in radians.
  var alpha = Math.atan2(Math.cos(deg2rad(epsilon)) * Math.sin(deg2rad(lambda)),
			 Math.cos(deg2rad(lambda)));
  // And declination, in radians.
  var delta = Math.asin(Math.sin(deg2rad(epsilon)) * Math.sin(deg2rad(lambda)));
  return [ alpha, delta ];
};

// Draw a polygon to show when it's night times.
const drawNightTimes = function(t, g) {
  var morningPos = [ meas.marginLeft + meas.dayLabelWidth, meas.marginTop ];
  var eveningPos = [ meas.marginLeft + meas.dayLabelWidth + 48 * meas.halfHourWidth, meas.marginTop ];
  for (i = 0; i < (t.length - 2); i++) {
    //console.log(t[i]);
    var y = meas.marginTop + i * meas.dayHeight;
    morningPos.push(meas.marginLeft + meas.dayLabelWidth + t[i][0] * (2 * meas.halfHourWidth));
    morningPos.push(y);
    eveningPos.push(meas.marginLeft + meas.dayLabelWidth + t[i][1] * (2 * meas.halfHourWidth));
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
    console.log("chose to load local schedule");
    callback(null, getLocalSchedule());
  } else if (loadLocal == false) {
    console.log("chose to load server schedule");
    // We get the file from a CGI script.
    var xhr = new XMLHttpRequest();
    xhr.open('GET', "/cgi-bin/scheduler.pl?request=load", true);
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
    console.log("something unexpected happened while loading schedule");
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

  var d = Math.abs(parseInt(sels[0]));
  var m = parseInt(sels[1]);
  var s = parseFloat(sels[2]);
  var n = d + m / 60.0 + s / 3600.0;
  if (isNeg) {
    n *= -1.0;
  }

  if (inHours) {
    n *= 15.0;
  }

  return n;
};

const atcaLat = 149.5501388;

// Given some coordinates c (an array with RA, Dec in degrees),
// on a Date d, calculate the rise hour and set hour in the day.
const calculateSourceStuff = function(c, d) {
  var mjd = date2mjd(d);
  var haset = haset_azel(c[1], atcaLat, 0);
  var riseHour = hourBounds((c[0] - haset) / 15);
  var setHour = hourBounds((c[0] + haset) / 15);
  var zlst = 24 * mjd2lst(mjd, (atcaLat / 360.0), 0);
  var riseDayHour = hoursUntilLst(zlst, riseHour);
  var setDayHour = hoursUntilLst(zlst, setHour);

  return [ riseDayHour, setDayHour ];
};

const calculateSunStuff = function(d) {
  var mjd = date2mjd(d);
  var sp = sunPosition(mjd);
  return calculateSourceStuff(sp.map(rad2deg), d);
  
  var decd = rad2deg(sp[1]);
  var haset = haset_azel(decd, 149.5501388, 0);
  var hour = degreesBounds(rad2deg(sp[0]));
  var riseHour = hourBounds((hour - haset) / 15);
  var setHour = hourBounds((hour + haset) / 15);
  var zlst = 24 * mjd2lst(mjd, (149.5501388 / 360.0), 0);
  var riseDayHour = hoursUntilLst(zlst, riseHour);
  var setDayHour = hoursUntilLst(zlst, setHour);
  return [ riseDayHour, setDayHour ];
};

// This contains all the nodes for each project in the table.
var tableRows = {};

// A helper function.
const makeElement = function(type, text, attrs) {
  var e = document.createElement(type);
  if ((typeof text != "undefined") && (text != null)) {
    e.innerHTML = text;
  }
  if (typeof attrs != "undefined") {
    for (var a in attrs) {
      if (attrs.hasOwnProperty(a)) {
	var n = document.createAttribute(a);
	n.value = attrs[a];
	e.setAttributeNode(n);
      }
    }
  }

  return e;
};

const legacyProjects = [ "C3132", "C3145", "C3152", "C3157" ];
const legacyLimit = 400; // Hours.
const projectLimit = 300; // Hours

// Make a summary of the current state of the projects.
const summariseProjects = function() {
  var r = [];

  var allProjects = scheduleData.program.project;
  for (var i = 0; i < allProjects.length; i++) {
    var s = { 'ident': allProjects[i].ident };
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
  var r = { 'arrays': [],
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

  // The total time available for the semester (in hours).
  r.timeSummary.available = (semesterEnd.getTime() -
			     semesterStart.getTime()) / (1000 * 3600);

  // Make the array summary object for each different possible score.
  var minScore = 0.0;
  var maxScore = 5.0;
  var scoreInterval = 0.1;
  for (var score = minScore; score <= maxScore; score += scoreInterval) {
    r.arrays.push({ 'score': Math.floor(score * 10) / 10,
		    '6km': { 'a': 0, 'b': 0, 'c': 0, 'd': 0, 'any': 0 },
		    '1.5km': { 'a': 0, 'b': 0, 'c': 0, 'd': 0, 'any': 0 },
		    '750m': { 'a': 0, 'b': 0, 'c': 0, 'd': 0, 'any': 0 },
		    'compact': { 'ew367': 0, 'ew352': 0, 'any': 0 },
		    'hybrid': { 'h214': 0, 'h168': 0, 'h75': 0, 'any': 0 },
		    'any': { 'any': 0 }
		  });
  }
  
  var allProjects = scheduleData.program.project;
  for (var i = 0; i < allProjects.length; i++) {
    //console.log(allProjects[i]);
    var slots = allProjects[i].slot;
    var isCalibration = false;
    if (allProjects[i].ident == "C007") {
      //console.log("calibration");
      isCalibration = true;
    }
    var isLegacy = false;
    if (legacyProjects.indexOf(allProjects[i].ident) >= 0) {
      //console.log("legacy");
      isLegacy = true;
    }
    var isVlbi = false;
    if (allProjects[i].ident == "VLBI") {
      //console.log("VLBI");
      isVlbi = true;
    }
    var isMaintenance = false;
    if ((allProjects[i].ident == "MAINT") ||
	(allProjects[i].ident == "CONFIG") ||
	(allProjects[i].ident == "CABB")) {
      //console.log("maintenance");
      isMaintenance = true;
    }
    var isNapa = false;
    if (/^NAPA/.test(allProjects[i].title)) {
      //console.log("NAPA");
      isNapa = true;
    }
    
    var projectTotalTime = 0;
    for (var j = 0; j < slots.length; j++) {
      if ((!isLegacy && (projectTotalTime >= projectLimit)) ||
	  (isLegacy && (projectTotalTime >= legacyLimit))) {
	break;
      }
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

      // Add to the correct array.
      if (!isMaintenance && !isVlbi && !isNapa) {
	for (var sarr = 0; sarr < r.arrays.length; sarr++) {
	  if (slots[j].rating < r.arrays[sarr].score) {
	    break;
	  }
	  if ((slots[j].array == "6a") || (slots[j].array == "6b") ||
	      (slots[j].array == "6c") || (slots[j].array == "6d") ||
	      (slots[j].array == "any6")) {
	    var v = slots[j].array.replace("6", "");
	    r['arrays'][sarr]["6km"][v] += slots[j].requested_duration;
	  } else if ((slots[j].array == "1.5a") || (slots[j].array == "1.5b") ||
		     (slots[j].array == "1.5c") || (slots[j].array == "1.5d") ||
		     (slots[j].array == "any1.5")) {
	    var v = slots[j].array.replace("1.5", "");
	    r['arrays'][sarr]["1.5km"][v] += slots[j].requested_duration;
	  } else if ((slots[j].array == "750a") || (slots[j].array == "750b") ||
		     (slots[j].array == "750c") || (slots[j].array == "750d") ||
		     (slots[j].array == "any750")) {
	    var v = slots[j].array.replace("750", "");
	    r['arrays'][sarr]["750m"][v] += slots[j].requested_duration;
	  } else if ((slots[j].array == "ew352") || (slots[j].array == "ew367") ||
		     (slots[j].array == "anycompact")) {
	    var v = slots[j].array.replace("compact", "");
	    r['arrays'][sarr]["compact"][v] += slots[j].requested_duration;
	  } else if ((slots[j].array == "h168") || (slots[j].array == "h214") ||
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
	}
      }
    }
  }

  return r;
};

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

const datetimeToSmallString = function(dts) {
  var dt = new Date(dts * 1000);
  return (dt.getDate() + "/" + (dt.getMonth() + 1));
};

// A little helper function to do things to a DOM element.
const fillId = function(id, text, addClasses, remClasses) {
  // Try to find the ID.
  var e = document.getElementById(id);
  if ((typeof e == "undefined") || (e == "undefined")) {
    console.log("cannot find DOM element with id " + id);
    return;
  }

  if ((typeof text != "undefined") && (text != null)) {
    e.innerHTML = text;
  }

  domAddClasses(e, addClasses);

  // Do we want to remove one or more classes.
  if ((typeof remClasses != "undefined") &&
      (remClasses != null)) {
    if (remClasses instanceof Array) {
      for (var i = 0; i < remClasses.length; i++) {
	if (e.classList.contains(remClasses[i])) {
	  e.classList.remove(remClasses[i]);
	}
      }
    } else {
      if (e.classList.contains(remClasses)) {
	e.classList.remove(remClasses);
      }
    }
  }
  
};

var previouslySelectedProject = null;
var previouslySelectedSlot = null;

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
  if (previouslySelectedProject == project) {
    return;
  } else if (previouslySelectedProject != null) {
    fillId("row-" + previouslySelectedProject.details.ident, null,
	   null, "selectedProject");
    previouslySelectedProject = null;
    previouslySelectedSlot = null;
  }
  
  // Select the row in the table.
  previouslySelectedProject = project;
  fillId("row-" + project.details.ident, null, "selectedProject");
  
  // Display the vital statistics.
  console.log(project);
  fillId("projectselectedIdent", project.details.ident);
  fillId("projectselectedPI", project.details.PI);
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
  
  // Make a table with each of the slots.
  // Empty the current table.
  var slotTable = emptyDomNode("projectslotsSelectionBody");
  for (var i = 0; i < project.details.slot.length; i++) {
    var s = project.details.slot[i];
    var rid = "slotrow-" + project.details.ident + "-" + i;
    var tr = makeElement("tr", null, {
      'id': rid
    });
    slotTable.appendChild(tr);
    var tsel = makeElement("th", "&nbsp;", {
      'id': "slotselected-" + project.details.ident + "-" + i
    });
    tr.appendChild(tsel);
    var td = makeElement("td", s.array.toUpperCase());
    tr.appendChild(td);
    td = makeElement("td", s.bands.join(","));
    tr.appendChild(td);
    td = makeElement("td", s.bandwidth);
    tr.appendChild(td);
    td = makeElement("td", s.source);
    tr.appendChild(td);
    td = makeElement("td", s.scheduled_duration + " / " +
		     s.requested_duration);
    tr.appendChild(td);

    // Add a click handler on this row.
    addClickHandler(tr, slotSelectorGen(i));
  }
  
};

const calcDayNumber = function(d) {
  if (d instanceof Date) {
    return (Math.floor((d.getTime() - scheduleFirst.getTime()) / (86400 * 1000)) + 1);
  } else {
    return (Math.floor((d - (scheduleFirst.getTime() / 1000)) / 86400) + 1);
  }
};

const selectSlot = function(slotnumber) {
  var psp = previouslySelectedProject.details;
  // Highlight the table element.
  var hid = "slotselected-" + psp.ident +
      "-" + slotnumber;
  fillId(hid, "&nbsp;", "slotSelected");
  // Dehighlight the previously selected slot.
  if (previouslySelectedSlot != null) {
    var pid = "slotselected-" + psp.ident +
	"-" + previouslySelectedSlot;
    fillId(pid, "&nbsp;", null, "slotSelected");
  }
  previouslySelectedSlot = slotnumber;
  
  // Remove any previous restrictions from the canvas.
  constraintBoxGroup.destroyChildren();
  
  // Work out the restrictions and put them on the canvas.
  // Begin with bad dates.
  for (var i = 0;
       i < psp.excluded_dates.length; i++) {
    // Which day needs drawing.
    /*var daynum = Math.floor((psp.excluded_dates[i] -
      (scheduleFirst.getTime() / 1000)) / 86400) + 1;*/
    var daynum = calcDayNumber(psp.excluded_dates[i]);
    drawDay(daynum, null, null, false, "red", [ [ 0, 24 ] ],
	    constraintBoxGroup);
  }
  // Then LST.
  var sourceTimes = allDates.forEach(function(d) {
    var ra = stringToDegrees(psp.slot[previouslySelectedSlot].position.ra, true);
    var dec = stringToDegrees(psp.slot[previouslySelectedSlot].position.dec, false);
    var sourceRiseSets = calculateSourceStuff([ ra, dec ], d);
    var daynum = calcDayNumber(d) - 1;
    var tplots = [ sourceRiseSets ];
    if (sourceRiseSets[0] > sourceRiseSets[1]) {
      // Backwards order.
      tplots = [ [ sourceRiseSets[0], 24 ], [ 0, sourceRiseSets[1] ] ];
    }

    drawDay(daynum, null, null, false, "orange", tplots, constraintBoxGroup);
    return sourceRiseSets;
  });
  console.log(sourceTimes);

  constraintLayer.draw();
  
  // Scroll to the right place if we have it already
  // scheduled, or the first good date.
  
  
};

const slotSelectorGen = function(sn) {
  return function() {
    selectSlot(sn);
  };
};

const emptyDomNode = function(id) {
  var n = document.getElementById(id);

  if ((typeof n != "undefined") && (n != "undefined")) {
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
      var td = makeElement("td", p.ident);
      // Check if this has a colour associated.
      if (p.hasOwnProperty("colour")) {
	var st = document.createAttribute("style");
	st.value = "background-color: #" + p.colour;
	td.setAttributeNode(st);
      }
      // We put an event handler on this to show its details.
      addClickHandler(td, projectClicker(p.ident));
      r.appendChild(td);
      // The rating element never changes.
      td = makeElement("td", p.rating);
      r.appendChild(td);
      // The scheduled time element will need to be changed.
      td = makeElement("td", "NN", {
	'id': "scheduledTime-" + p.ident });
      r.appendChild(td);
      // The requested time does not need to be changed.
      td = makeElement("td", p.requestedTime);
      r.appendChild(td);
      // The scheduled slots element will need to be changed.
      td = makeElement("td", "NN", {
	'id': "scheduledSlots-" + p.ident });
      r.appendChild(td);
      // The requested slots does not need to be changed.
      td = makeElement("td", p.requestedSlots);
      r.appendChild(td);
    }
  }

  // Update the table cells and rows.
  for (var i = 0; i < sortedProjects.length; i++) {
    var p = sortedProjects[i];
    var scheduledTime = document.getElementById("scheduledTime-" +
						p.ident);
    scheduledTime.innerHTML = p.scheduledTime;
    var scheduledSlots = document.getElementById("scheduledSlots-" +
						 p.ident);
    scheduledSlots.innerHTML = p.scheduledSlots;
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
	  for (var l in semsum.arrayLabels[i][k]) {
	    if (semsum.arrayLabels[i][k].hasOwnProperty(l)) {
	      tm = tm[l]
	      label = semsum.arrayLabels[i][k][l];
	    }
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
	  for (var atype in semsum.arrays[i][arr]) {
	    if (semsum.arrays[i][arr].hasOwnProperty(atype)) {
	      totalTime += semsum.arrays[i][arr][atype];
	    }
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
	    for (var l in semsum.arrayLabels[j][k]) {
	      if (semsum.arrayLabels[j][k].hasOwnProperty(l)) {
		tm = tm[l];
		tlab = semsum.arrayLabels[j][k][l];
	      }
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
    makeTableCell("th", "Legacy:", r);
    savedDomNodes.legacyTime = makeTableCell("td", "NN", r, {
      'id': "sst-legacy-allocation" });
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
    makeTableCell("th", "CABB:", r);
    savedDomNodes.cabbTime = makeTableCell("td", "NN", r, {
      'id': "sst-cabb-allocation" });
    
  }

  // Update the table.
  savedDomNodes.availableTime.innerHTML =
    semsum.timeSummary.available - semsum.timeSummary.scheduled -
    semsum.timeSummary.calibration - semsum.timeSummary.legacy -
    semsum.timeSummary.vlbi - semsum.timeSummary.maintenance;
  savedDomNodes.scheduledTime.innerHTML = semsum.timeSummary.scheduled;
  savedDomNodes.remainingTime.innerHTML = (semsum.timeSummary.requested -
					   semsum.timeSummary.scheduled);
  savedDomNodes.calibrationTime.innerHTML = semsum.timeSummary.calibration;
  savedDomNodes.legacyTime.innerHTML = semsum.timeSummary.legacy;
  savedDomNodes.vlbiTime.innerHTML = semsum.timeSummary.vlbi;
  savedDomNodes.maintenanceTime.innerHTML = semsum.timeSummary.maintenance;
  savedDomNodes.reconfigTime.innerHTML = semsum.timeSummary.nReconfigure;
  savedDomNodes.cabbTime.innerHTML = semsum.timeSummary.nCabb;

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
  var stage = new Konva.Stage({
    container: "schedtable",
    width: meas.width, height: meas.height
  });
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

  // Draw the initial array configurations.
  drawArrayConfigurations();
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

const drawConfiguration = function(title, start, end) {
  // Draw a box on the right.
  var nDaysSinceStart = (start - scheduleFirst.getTime()) / (86400 * 1000);
  var nDays = (end - start) / (86400 * 1000);

  var boxLeft = meas.marginLeft + meas.dayLabelWidth + meas.dayWidth;
  var boxTop = meas.marginTop + nDaysSinceStart * meas.dayHeight;
  var boxWidth = meas.arrayLabelWidth;
  var boxHeight = nDays * meas.dayHeight;
  
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
      align: "center", verticalAlign: "middle", text: title, fontSize: 20
    });
    totalHeight += labelHeight;
    boxHeight -= labelHeight;
    arrayGroup.add(arrayLabelString);
  }
  
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
    slots[0].scheduled_start = scheduleFirst.getTime();
  }

  var currentConfig = 0;
  // Go through all the configs until we find the next one.
  var minDiff = 365 * 86400 * 1000;
  while (true) {
    var nextConfig = -1;
    for (var i = 0; i < slots.length; i++) {
      if (i == currentConfig) {
	continue;
      }
      if (slots[i].scheduled_start == 0) {
	continue;
      }
      var tdiff = slots[i].scheduled_start - slots[currentConfig].scheduled_start;
      if (tdiff < minDiff) {
	tdiff = minDiff;
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
  }

  // Draw the last configuration.
  drawConfiguration(slots[currentConfig].array, slots[currentConfig].scheduled_start,
		    scheduleLast.getTime());

  arrayLayer.draw();
};

// Clear the part of the page which shows the available slots.
const clearSlotSelector = function() {
  fillId("projectselectedIdent", "NONE");
  fillId("projectselectedPI", "NOBODY");
  var projectselectedTable = document.getElementById("projectselected");
  projectselectedTable.style["background-color"] = "white";

  emptyDomNode("projectslotsSelectionBody");

  // Deselect the slots.
  // TODO

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
    console.log("Unable to retrieve data.");
    return;
  }

  // Keep the data for later.
  console.log(data);
  scheduleData = data;

  // Save the data locally.
  saveLocalSchedule();
  // Display some times.
  checkLocalTime(displayModificationTimes);

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
  } else {
    indicator.innerHTML = "OFFLINE";
  }
};

// Check what the server schedule modification time is.
const checkServerTime = function(callback) {
  if (navigator.onLine) {
    // We need to be online of course.
    var xhr = new XMLHttpRequest();
    xhr.open('GET', "/cgi-bin/scheduler.pl?request=loadtime", true);
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

const localKey = "atnfSchedule";

const getLocalSchedule = function() {
  // Try to get the schedule from our local storage.
  var localSchedule = window.localStorage.getItem(localKey);
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
    window.localStorage.setItem(localKey, JSON.stringify(scheduleData));
  }
  displayModificationTimes();
};

const saveScheduleToServer = function() {
  if (scheduleData != null) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", "/cgi-bin/scheduler.pl", true)
    xhr.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
    xhr.responseType = "json";
    xhr.onload = function() {
      var status = xhr.status;
      console.log(xhr.response);
      console.log(xhr.status);
      if (status === 200) {
	displayModificationTimes();
      } else {
	displayModificationTimes();
      }
    }
    //xhr.send({ "request": "save",
    //	       "schedule": JSON.stringify(scheduleData) });
    xhr.send("request=save&schedule=" + JSON.stringify(scheduleData));
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
  console.log(previouslySelectedProject);
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

// Configure some event handlers on existing nodes.
const staticEventHandlers = function() {
  // Enable the check box for nighttimes.
  var nc = document.getElementById("nighttime");
  nc.addEventListener("change", nighttimeChange);

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
};
staticEventHandlers();


// Start the process by loading the file.
const pageInitBootstrap = function() {
  return loadFile(pageInit, false);
};
checkServerTime(pageInitBootstrap);
checkLocalTime(pageInitBootstrap);

const stateChange = function() {
  showLineState();
};
// Set a handler for when the state changes.
window.addEventListener("online", stateChange);
window.addEventListener("offline", stateChange);
