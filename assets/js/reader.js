// Intercept link clicks and open externally via Flutter
document.addEventListener('click', function(e) {
  var anchor = e.target.closest('a[href]');
  if (anchor) {
    var href = anchor.getAttribute('href');
    if (href && (href.startsWith('http://') || href.startsWith('https://'))) {
      e.preventDefault();
      e.stopPropagation();
      ReaderChannel.postMessage('open-url:' + href);
    }
  }
}, true);

// Track for double-tap detection
var lastTapTime = 0;
var lastTapTarget = null;
var tapTimeout = null;

// Swipe detection: a deliberate sideways swipe changes chapter, but a scroll
// whose path curves sideways must not.
var touchStartX = 0;
var touchStartY = 0;
var touchStartTime = 0;
var touchStartScroll = 0;
var swipeAxis = null; // 'x' or 'y', decided once the finger has moved a bit
var swipeCancelled = false;
// Share of the screen width a swipe must cover; Flutter sets it from Settings.
var swipeDistance = 0.18;
window.setSwipeDistance = function(share) { swipeDistance = share; };

document.addEventListener('touchstart', function(e) {
  // A second finger (pinch) rules out a swipe for the whole gesture.
  if (e.touches.length > 1) { swipeCancelled = true; return; }
  touchStartX = e.touches[0].clientX;
  touchStartY = e.touches[0].clientY;
  touchStartTime = Date.now();
  touchStartScroll = window.scrollY;
  swipeAxis = null;
  swipeCancelled = false;
}, { passive: true });

document.addEventListener('touchmove', function(e) {
  if (swipeAxis || e.touches.length > 1) return;
  var dx = Math.abs(e.touches[0].clientX - touchStartX);
  var dy = Math.abs(e.touches[0].clientY - touchStartY);
  // Lock the direction early: unless the start is clearly sideways, this
  // touch is a scroll however far it drifts sideways later.
  if (dx > 12 || dy > 12) swipeAxis = dx > 2 * dy ? 'x' : 'y';
}, { passive: true });

document.addEventListener('touchend', function(e) {
  if (swipeCancelled || e.touches.length > 0 || swipeAxis !== 'x') return;
  // The page moved, so this was a scroll.
  if (Math.abs(window.scrollY - touchStartScroll) > 10) return;
  // Dragging to select text isn't a swipe.
  if (window.getSelection().toString().length > 0) return;

  var deltaX = e.changedTouches[0].clientX - touchStartX;
  var deltaY = e.changedTouches[0].clientY - touchStartY;
  var deltaTime = Date.now() - touchStartTime;
  // Far enough (set in Settings), mostly sideways overall, and quick.
  var minDistance = Math.max(40, window.innerWidth * swipeDistance);

  if (Math.abs(deltaX) > minDistance &&
      Math.abs(deltaX) > 2 * Math.abs(deltaY) &&
      deltaTime < 700) {
    if (deltaX > 0) {
      // Swipe right = previous chapter
      ReaderChannel.postMessage('prev');
    } else {
      // Swipe left = next chapter
      ReaderChannel.postMessage('next');
    }
  }
}, { passive: true });

// A tap between lines or beside the text lands on the paragraph itself; pick
// the sentence nearest the finger so double-tap starts where the user meant.
function sentenceAt(el, x, y) {
  if (!el || el.hasAttribute('data-sent')) return el;
  var spans = el.querySelectorAll('[data-sent]');
  var best = el, bestDist = Infinity;
  for (var i = 0; i < spans.length; i++) {
    var rects = spans[i].getClientRects();
    for (var j = 0; j < rects.length; j++) {
      var r = rects[j];
      var dx = x < r.left ? r.left - x : (x > r.right ? x - r.right : 0);
      var dy = y < r.top ? r.top - y : (y > r.bottom ? y - r.bottom : 0);
      var d = dx * dx + dy * dy;
      if (d < bestDist) { bestDist = d; best = spans[i]; }
    }
  }
  return best;
}

document.body.addEventListener('click', function(e) {
  var now = Date.now();

  // Check for double-tap on TTS paragraph/sentence FIRST
  // (before selection check, so browser's double-click text selection doesn't interfere)
  var target = sentenceAt(e.target.closest('[data-para]'), e.clientX, e.clientY);

  if (target && lastTapTarget === target && (now - lastTapTime) < 400) {
    // Double tap detected - skip to this paragraph/sentence
    clearTimeout(tapTimeout);
    // Clear any text selection that may have occurred
    window.getSelection().removeAllRanges();
    var paraIndex = target.getAttribute('data-para');
    var sentIndex = target.getAttribute('data-sent');
    if (sentIndex !== null) {
      ReaderChannel.postMessage('tts-skip:' + paraIndex + ':' + sentIndex);
    } else {
      ReaderChannel.postMessage('tts-skip:' + paraIndex);
    }
    lastTapTime = 0;
    lastTapTarget = null;
    e.preventDefault();
    e.stopPropagation();
    return;
  }

  // Don't trigger if user is selecting text (by dragging)
  if (window.getSelection().toString().length > 0) return;

  lastTapTime = now;
  lastTapTarget = target;

  // Delay single-tap to allow for double-tap detection
  clearTimeout(tapTimeout);
  tapTimeout = setTimeout(function() {
    // Single tap toggles UI (no more edge navigation)
    ReaderChannel.postMessage('toggle');
  }, target ? 400 : 0);
});

// TTS highlight functions
// Following: the page scrolls to keep the spoken sentence in view, until the
// user scrolls it out of view themselves. Flutter then shows "Back to reading";
// following resumes when that's tapped or the sentence is back on screen.
//
// While the user is scrolling (finger down, wheel or keys, or the page still
// gliding after they let go) the page never auto-scrolls; once it settles,
// following stays on only if the spoken sentence is still on screen.
window._ttsFollow = true;
var _touching = false, _userScrolling = false, _touchY = 0, _settleTimer;

document.addEventListener('touchstart', function(e) {
  _touching = true;
  _touchY = e.touches[0].clientY;
}, { passive: true });
document.addEventListener('touchmove', function(e) {
  if (Math.abs(e.touches[0].clientY - _touchY) > 8) _userScrolling = true;
}, { passive: true });
function endTouch() {
  _touching = false;
  scheduleSettle();
}
document.addEventListener('touchend', endTouch, { passive: true });
document.addEventListener('touchcancel', endTouch, { passive: true });

// Scrolling with a mouse wheel, trackpad or the keyboard (the Mac app) is the
// user scrolling just as a finger is: the page must not snap back to the
// spoken sentence, and "Back to reading" shows once that is out of view.
function userScrolled() {
  _userScrolling = true;
  scheduleSettle();
}
document.addEventListener('wheel', function(e) {
  // Pinch-zoom arrives as a wheel event with ctrlKey; sideways doesn't scroll.
  if (e.ctrlKey || !e.deltaY) return;
  userScrolled();
}, { passive: true });

var scrollKeys = { ArrowUp: 1, ArrowDown: 1, PageUp: 1, PageDown: 1, Home: 1, End: 1, ' ': 1 };
document.addEventListener('keydown', function(e) {
  if (scrollKeys[e.key]) {
    userScrolled();
    return;
  }
  // Left/Right turn to the previous/next chapter, as a swipe does. With a
  // modifier they mean something else (extend the selection, go back).
  if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey || e.repeat) return;
  if (e.key === 'ArrowLeft') {
    ReaderChannel.postMessage('prev');
  } else if (e.key === 'ArrowRight') {
    ReaderChannel.postMessage('next');
  }
});

// Called on every scroll event and when the finger lifts: once nothing has
// moved for a moment, decide whether to keep following.
function scheduleSettle() {
  clearTimeout(_settleTimer);
  _settleTimer = setTimeout(function() {
    if (_touching || !_userScrolling) return;
    _userScrolling = false;
    var cur = document.querySelector('.tts-highlight');
    setFollow(cur ? inView(cur) : true);
  }, 250);
}

function inView(el) {
  var r = el.getBoundingClientRect();
  return r.bottom > 0 && r.top < window.innerHeight;
}

function setFollow(on) {
  if (window._ttsFollow === on) return;
  window._ttsFollow = on;
  ReaderChannel.postMessage(on ? 'tts-follow:on' : 'tts-follow:off');
}

function clearTts() {
  var prev = document.querySelectorAll('.tts-highlight');
  for (var i = 0; i < prev.length; i++) prev[i].classList.remove('tts-highlight');
}

// [els] are the pieces of one sentence (several when it crosses formatting),
// or a single paragraph.
function showTts(els) {
  clearTts();
  for (var i = 0; i < els.length; i++) els[i].classList.add('tts-highlight');
  var el = els[0];
  if (_userScrolling) return; // never fight the user's finger
  if (window._ttsFollow) {
    el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  } else if (inView(el)) {
    setFollow(true);
  }
}

window.ttsHighlightParagraph = function(index) {
  var el = document.querySelector('.tts-para[data-para="' + index + '"]');
  if (el) showTts([el]);
};

window.ttsHighlightSentence = function(paraIndex, sentIndex) {
  var els = document.querySelectorAll('[data-para="' + paraIndex + '"][data-sent="' + sentIndex + '"]');
  if (els.length) {
    showTts(els);
  } else {
    // Fallback to paragraph highlight if no sentence span found
    window.ttsHighlightParagraph(paraIndex);
  }
};

window.ttsClearHighlight = function() {
  clearTts();
  setFollow(true);
};

window.ttsFollowNow = function() {
  _userScrolling = false;
  setFollow(true);
  var cur = document.querySelector('.tts-highlight');
  if (cur) cur.scrollIntoView({ behavior: 'smooth', block: 'center' });
};

// Where Play should start: the preferred position if it's on screen,
// otherwise the first sentence/paragraph visible below [top] (the app bar).
// Returns "para:sent", "para", or "".
window.ttsVisibleStart = function(top, prefPara, prefSent) {
  var visible = function(el) {
    var r = el.getBoundingClientRect();
    return r.bottom > top && r.top < window.innerHeight;
  };
  if (prefPara >= 0) {
    var pref = document.querySelector(prefSent >= 0
      ? '[data-para="' + prefPara + '"][data-sent="' + prefSent + '"]'
      : '.tts-para[data-para="' + prefPara + '"]');
    if (pref && visible(pref)) return prefSent >= 0 ? prefPara + ':' + prefSent : '' + prefPara;
  }
  var paras = document.querySelectorAll('.tts-para');
  for (var i = 0; i < paras.length; i++) {
    if (!visible(paras[i])) continue;
    var p = paras[i].getAttribute('data-para');
    var sents = paras[i].querySelectorAll('[data-sent]');
    for (var j = 0; j < sents.length; j++) {
      if (visible(sents[j])) return p + ':' + sents[j].getAttribute('data-sent');
    }
    return p;
  }
  return '';
};

// After a chapter change during read-aloud: wait [delay] ms for any jump to
// the reader's spot (bookmark, search result, remembered place), then for the
// page to stop scrolling, and report where reading should carry on.
window.ttsContinueFrom = function(top, prefPara, prefSent, delay) {
  var last = -1, still = 0;
  var check = function() {
    if (window.scrollY === last) {
      still++;
    } else {
      still = 0;
      last = window.scrollY;
    }
    if (still >= 3) {
      ReaderChannel.postMessage('tts-start:' + window.ttsVisibleStart(top, prefPara, prefSent));
    } else {
      setTimeout(check, 50);
    }
  };
  setTimeout(check, delay);
};

// Scroll listener to update Flutter state
var scrollTimeout;
window.addEventListener('scroll', function() {
  clearTimeout(scrollTimeout);
  scrollTimeout = setTimeout(function() {
    ReaderChannel.postMessage('scroll:' + window.scrollY);
  }, 200);
  scheduleSettle();
});

// ── Highlight system ──────────────────────────────────────────
// Listen for text selection changes
var selectionTimeout;
// Report the selection, plus where it starts and ends on screen so the
// highlight pill can sit just below the last selected word.
function reportSelection() {
  var sel = window.getSelection();
  if (sel && sel.toString().trim().length > 0 && sel.rangeCount > 0) {
    var range = sel.getRangeAt(0);
    // Calculate text offset within the body
    var preRange = document.createRange();
    preRange.selectNodeContents(document.body);
    preRange.setEnd(range.startContainer, range.startOffset);
    var startOffset = preRange.toString().length;
    // Counted the same way as the start (characters of the text nodes);
    // sel.toString() is the rendered text, with line breaks added.
    var endOffset = startOffset + range.toString().length;
    var rects = range.getClientRects();
    var first = rects.length ? rects[0] : range.getBoundingClientRect();
    var last = rects.length ? rects[rects.length - 1] : first;
    ReaderChannel.postMessage('selection:' + JSON.stringify({
      text: sel.toString().trim(),
      startOffset: startOffset,
      endOffset: endOffset,
      top: first.top,
      bottom: last.bottom,
      right: last.right
    }));
  } else {
    ReaderChannel.postMessage('selection-cleared');
  }
}
document.addEventListener('selectionchange', function() {
  clearTimeout(selectionTimeout);
  selectionTimeout = setTimeout(reportSelection, 150);
});
window.addEventListener('scroll', function() {
  if (window.getSelection().toString().length === 0) return;
  clearTimeout(selectionTimeout);
  selectionTimeout = setTimeout(reportSelection, 150);
});

// Apply a highlight visually
window.applyHighlight = function(startOffset, endOffset, color, hlId) {
  var body = document.body;
  var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null, false);
  var charCount = 0;
  var nodesToWrap = [];

  while (walker.nextNode()) {
    var node = walker.currentNode;
    var nodeLen = node.nodeValue.length;
    var nodeStart = charCount;
    var nodeEnd = charCount + nodeLen;

    if (nodeEnd > startOffset && nodeStart < endOffset) {
      var wrapStart = Math.max(0, startOffset - nodeStart);
      var wrapEnd = Math.min(nodeLen, endOffset - nodeStart);
      nodesToWrap.push({ node: node, start: wrapStart, end: wrapEnd });
    }
    charCount += nodeLen;
    if (charCount >= endOffset) break;
  }

  for (var i = nodesToWrap.length - 1; i >= 0; i--) {
    var item = nodesToWrap[i];
    var range = document.createRange();
    range.setStart(item.node, item.start);
    range.setEnd(item.node, item.end);
    var mark = document.createElement('mark');
    mark.className = 'user-highlight';
    mark.setAttribute('data-hl-id', hlId);
    // Inline and !important: the page's stylesheet clears every background.
    mark.style.setProperty('background-color', color, 'important');
    // The range lies inside one text node, so it can always be wrapped.
    range.surroundContents(mark);
  }
  // Clear selection after highlighting
  window.getSelection().removeAllRanges();
};

// Remove a highlight by ID
window.removeHighlight = function(hlId) {
  var marks = document.querySelectorAll('mark[data-hl-id="' + hlId + '"]');
  marks.forEach(function(mark) {
    var parent = mark.parentNode;
    while (mark.firstChild) {
      parent.insertBefore(mark.firstChild, mark);
    }
    parent.removeChild(mark);
    parent.normalize();
  });
};

// Restore all highlights from JSON
window.restoreHighlights = function(highlightsJson) {
  var highlights = JSON.parse(highlightsJson);
  highlights.forEach(function(h) {
    window.applyHighlight(h.startOffset, h.endOffset, h.color, h.id);
  });
};

// Scroll to a specific highlight by ID
window.scrollToHighlight = function(hlId) {
  var el = document.querySelector('mark[data-hl-id="' + hlId + '"]');
  if (el) {
    el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }
};
