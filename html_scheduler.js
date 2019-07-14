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
  margin: 60,
  // The width of the right-side area where we see the individual elements.
  elementWidth: 0,
  // The height of a single day.
  dayHeight: 40,
  // The width of the label which holds the date string.
  dayLabelWidth: 140,  
  // The width of the array panel.
  arrayLabelWidth: 60
};

// The number of days to display (basically half a leap year, plus a few.
const nDays = (366 / 2) + 4;

// Compute some secondary measurements from the primary measurements.
// The width of an entire day.
meas.dayWidth = 48 * meas.halfHourWidth;
// The canvas width.
meas.width = meas.dayWidth + 3 * meas.margin + meas.elementWidth + meas.dayLabelWidth;
// The canvas height.
meas.height = nDays * meas.dayHeight + 2 * meas.margin;

// Function that draws the n-th day in the schedule.
// Takes the day number n, the Date d and the group g to draw to.
const drawDay = function(n, d, g) {
  // The date is shown in the day label box.
  var dayLabelOpts = {
    x: meas.margin, y: (meas.margin + n * meas.dayHeight),
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
    x: meas.margin + 5, y: (meas.margin + n * meas.dayHeight),
    text: printDate(d), fontSize: 16, verticalAlign: "middle",
    height: meas.dayHeight
  });
  // Draw the outline of the box for the hours.
  var dayBox = new Konva.Rect({
    x: meas.margin + meas.dayLabelWidth, y: (meas.margin + n * meas.dayHeight),
    width: meas.dayWidth, height: meas.dayHeight,
    stroke: "black", strokeWidth: 2
  });
  g.add(dayLabelBox);
  g.add(dateString);
  g.add(dayBox);

  // Draw an hour grid.
  for (var j = 0; j < 24; j++) {
    fillColour = "#00aa00";
    if (j % 2) {
      fillColour = "#ffffff";
    }
    var hourRect = new Konva.Rect({
      x: (meas.margin + meas.dayLabelWidth + j * 2 * meas.halfHourWidth),
      y: (meas.margin + n * meas.dayHeight + 1),
      width: (2 * meas.halfHourWidth), height: (meas.dayHeight - 2),
      fill: fillColour, stroke: fillColour, strokeWidth: 0
    });
    g.add(hourRect);
  }
};

// Function that draws the hour labels at the top of the schedule.
// Need to supply the group g to draw to.
const drawHourLabels = function(g) {
  for (var j = 0; j <= 24; j += 2) {
    var hourLabel = new Konva.Text({
      x: (meas.margin + meas.dayLabelWidth + j * 2 * meas.halfHourWidth),
      y: meas.margin, text: "" + (j % 24), fontSize: 20
    });
    hourLabel.offsetX(hourLabel.width() / 2);
    hourLabel.offsetY(hourLabel.height() * 1.1);
    g.add(hourLabel);
    var utcLabel = new Konva.Text({
      x: (meas.margin + meas.dayLabelWidth + j * 2 * meas.halfHourWidth),
      y: meas.margin, text: "" + ((j + 14) % 24), fontSize: 20
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

// Draw an LST line on a particular day.
const lstDraw = function(n, d, l, p, g) {
  // Calculate the LST at midnight this day.
  var zlst = 24 * mjd2lst(date2mjd(d), (149.5501388 / 360.0), 0);
  var midHours = hoursUntilLst(zlst, l);
  var topHours = midHours + (2 / 60);
  var bottomHours = midHours - (2 / 60);
  var topX = meas.margin + meas.dayLabelWidth + (topHours * (2 * meas.halfHourWidth));
  var bottomX = meas.margin + meas.dayLabelWidth + (bottomHours * (2 * meas.halfHourWidth));
  var lobj = p;
  lobj.points = [ topX, (meas.margin + n * meas.dayHeight),
		  bottomX, (meas.margin + (n + 1) * meas.dayHeight) ];
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
  var morningPos = [ meas.margin + meas.dayLabelWidth, meas.margin ];
  var eveningPos = [ meas.margin + meas.dayLabelWidth + 48 * meas.halfHourWidth, meas.margin ];
  for (i = 0; i < (t.length - 2); i++) {
    //console.log(t[i]);
    var y = meas.margin + i * meas.dayHeight;
    morningPos.push(meas.margin + meas.dayLabelWidth + t[i][0] * (2 * meas.halfHourWidth));
    morningPos.push(y);
    eveningPos.push(meas.margin + meas.dayLabelWidth + t[i][1] * (2 * meas.halfHourWidth));
    eveningPos.push(y);
  }
  morningPos.push(meas.margin + meas.dayLabelWidth);
  morningPos.push(meas.margin + (nDays - 1) * meas.dayHeight);
  eveningPos.push(meas.margin + meas.dayLabelWidth + 48 * meas.halfHourWidth);
  eveningPos.push(meas.margin + (nDays - 1) * meas.dayHeight);
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

// Load the schedule JSON file.
const loadFile = function(callback) {
  // The name of the JSON file.
  var schedJson = "schedule.json";

  // Grab this file.
  var xhr = new XMLHttpRequest();
  xhr.open('GET', schedJson, true);
  xhr.responseType = "json";
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

const calculateSunStuff = function(d) {
  var mjd = date2mjd(d);
  var sp = sunPosition(mjd);
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


// Do all the things needed to create the page, after the schedule
// has been loaded.
const createPage = function(status, data) {

  if ((typeof data == "undefined") || (data == null)) {
    console.log("Unable to retrieve data.");
    return;
  }

  // Keep the data for later.
  scheduleData = data;
  
  // Set up the schedule.
  var re = /^(\d\d\d\d)(\D\D\D)$/g;
  var rmatch = re.exec(data.program.term.term);
  var semester = rmatch[2]
  var year = parseInt(rmatch[1]);
  
  // Get the date for the first day of the schedule.
  var semesterStart = new Date();
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
  var allDates = allSunDates.slice(1, nDays);
  scheduleLast = new Date();
  scheduleLast.setTime(allDates[allDates.length - 1].getTime() + 86400 * 1000);
  
  // Set up the canvas.
  var stage = new Konva.Stage({
    container: "schedtable",
    width: meas.width, height: meas.height
  });
  
  // Make the background layer.
  var backgroundLayer = new Konva.Layer();
  // Add to this a group which will contain all the day boxes.
  var dayBoxGroup = new Konva.Group({
    draggable: false
  });
  
  allDates.forEach(function(d, i) {
    drawDay(i, d, dayBoxGroup);
  });
  // Draw the hour labels at the top.
  drawHourLabels(dayBoxGroup);
  // Add the background groups and layer to the stage.
  backgroundLayer.add(dayBoxGroup);
  stage.add(backgroundLayer);
  
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
  for (var i = 0; i < allProjects.length; i++) {
    if (name == allProjects[i].ident) {
      return allProjects[i];
    }
  }

  return null;
};

const drawConfiguration = function(title, start, end) {
  // Draw a box on the right.
  var nDaysSinceStart = (start - scheduleFirst.getTime()) / (86400 * 1000);
  var nDays = (end - start) / (86400 * 1000);

  var boxLeft = meas.margin + meas.dayLabelWidth + meas.dayWidth;
  var boxTop = meas.margin + nDaysSinceStart * meas.dayHeight;
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
  console.log(configs);
  var slots = configs.slot;

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

    drawConfiguration(slots[currentConfig].array, slots[currentConfig].scheduled_start,
		      slots[nextConfig].scheduled_start);
  }

  // Draw the last configuration.
  drawConfiguration(slots[currentConfig].array, slots[currentConfig].scheduled_start,
		    scheduleLast.getTime());

  arrayLayer.draw();
};

// Start the process by loading the file.
loadFile(createPage);

