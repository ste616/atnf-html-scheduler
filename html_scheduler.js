/**
 * HTML scheduler for ATCA and Parkes.
 * Jamie Stevens 2019
 */

// Function to take a JS Date and output the string that would
// go in the left date box.
const printDate = function(d) {
  var m = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun",
	    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ];
  var w = [ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" ];
  var r = w[d.getDay()] + " " + m[d.getMonth()] + " " + d.getDate() +
      " (" + Math.floor(date2mjd(d)) + ")";
  return r;
};

// An object to hold all our measurements.
var meas = {
  // The width of a half-hour (the smallest increment we schedule to).
  halfHourWidth: 12,
  // The margin around the schedule box.
  margin: 60,
  // The width of the right-side area where we see the individual elements.
  elementWidth: 300,
  // The height of a single day.
  dayHeight: 40,
  // The width of the label which holds the date string.
  dayLabelWidth: 140
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
  var dayLabelBox = new Konva.Rect({
    x: meas.margin, y: (meas.margin + n * meas.dayHeight),
    width: meas.dayLabelWidth, height: meas.dayHeight,
    stroke: "black", strokeWidth: 2
  });
  // Make the string to go into this box.
  var dateString = new Konva.Text({
    x: meas.margin + 5, y: (meas.margin + n * meas.dayHeight + 5),
    text: printDate(d), fontSize: 16
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
var numberBounds = function(n, b) {
  while (n > b) {
    n -= b;
  }
  while (n < 0) {
    n += b;
  }
  return n;
};

// Given any number, put it between 0 and 1.
var turnFraction = function(f) {
  return numberBounds(f, 1);
};

// Calculate the sidereal time at Greenwich, given an MJD.
var gst = function(mjd, dUT1) {
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
var mjd2lst = function(mjd, longitude, dUT1) {
  var lst = turnFraction(gst(mjd, dUT1) + longitude);
  return lst;
};

// Given some sidereal time at time 0, work out how many real hours
// until some nominated sidereal time.
var hoursUntilLst = function(zlst, dlst) {
  if (dlst < zlst) {
    dlst += 24;
  }

  return ((dlst - zlst) / 1.002737909350795);
};

// Draw an LST line on a particular day.
var lstDraw = function(n, d, l, p, g) {
  // Calculate the LST at midnight this day.
  var zlst = 24 * mjd2lst(date2mjd(d), (149.5501388 / 360.0), 0);
  var midHours = hoursUntilLst(zlst, l);
  console.log(midHours);
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

// Set up the schedule.
var semester = "APR";
var year = 2019;

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
var scheduleFirst = new Date();
scheduleFirst.setTime(semesterStart.getTime() - 3 * 86400 * 1000);
// Make all the dates.
var allDates = [];
for (var i = 0; i < nDays; i++) {
  var pdate = new Date();
  pdate.setTime(scheduleFirst.getTime() + i * 86400 * 1000);
  allDates.push(pdate);
}

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
		 { stroke: 'blue', dash: [ 33, 10 ] },
		 { stroke: 'orange', dash: [ 33, 10 ] },
		 { stroke: 'grey', dash: [ 24, 11 ] } ];
for (var i = 0; i < lstLines.length; i++) {
  allDates.forEach(function(d, j) {
    lstDraw(j, allDates[j], lstLines[i], lstProps[i], timeGroup);
  });
}
topLayer.add(timeGroup);
stage.add(topLayer);
