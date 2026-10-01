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

// Swipe detection
var touchStartX = 0;
var touchStartY = 0;
var touchStartTime = 0;

document.addEventListener('touchstart', function(e) {
  touchStartX = e.touches[0].clientX;
  touchStartY = e.touches[0].clientY;
  touchStartTime = Date.now();
}, { passive: true });

document.addEventListener('touchend', function(e) {
  var touchEndX = e.changedTouches[0].clientX;
  var touchEndY = e.changedTouches[0].clientY;
  var deltaX = touchEndX - touchStartX;
  var deltaY = touchEndY - touchStartY;
  var deltaTime = Date.now() - touchStartTime;

  // Only detect horizontal swipes (not vertical scrolling)
  // Require: >50px horizontal, <150px vertical, <700ms duration
  if (Math.abs(deltaX) > 50 && Math.abs(deltaY) < 150 && deltaTime < 700) {
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
// While the user is scrolling (finger down, or the page still gliding after
// they let go) the page never auto-scrolls; once it settles, following stays
// on only if the spoken sentence is still on screen.
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

// Scroll listener to update Flutter state
var scrollTimeout;
window.addEventListener('scroll', function() {
  clearTimeout(scrollTimeout);
  scrollTimeout = setTimeout(function() {
    ReaderChannel.postMessage('scroll:' + window.scrollY);
  }, 200);
  scheduleSettle();
});

// Search functions
window._searchMatches = [];
window._searchIndex = -1;

window.searchFind = function(query) {
  window.searchClear();
  if (!query || query.length === 0) {
    ReaderChannel.postMessage('search-results:0');
    return;
  }
  var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
  var textNodes = [];
  while (walker.nextNode()) textNodes.push(walker.currentNode);
  var lowerQ = query.toLowerCase();
  var count = 0;
  textNodes.forEach(function(node) {
    var text = node.nodeValue;
    var lower = text.toLowerCase();
    var idx = lower.indexOf(lowerQ);
    if (idx === -1) return;
    var parent = node.parentNode;
    var frag = document.createDocumentFragment();
    var last = 0;
    while (idx !== -1) {
      if (idx > last) frag.appendChild(document.createTextNode(text.substring(last, idx)));
      var mark = document.createElement('mark');
      mark.className = 'search-match';
      mark.setAttribute('data-si', count.toString());
      mark.textContent = text.substring(idx, idx + query.length);
      frag.appendChild(mark);
      count++;
      last = idx + query.length;
      idx = lower.indexOf(lowerQ, last);
    }
    if (last < text.length) frag.appendChild(document.createTextNode(text.substring(last)));
    parent.replaceChild(frag, node);
  });
  window._searchMatches = document.querySelectorAll('.search-match');
  if (count > 0) {
    window._searchIndex = 0;
    window._searchMatches[0].classList.add('search-current');
    window._searchMatches[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
  ReaderChannel.postMessage('search-results:' + count);
};

window.searchNext = function() {
  var m = window._searchMatches;
  if (!m || m.length === 0) return;
  m[window._searchIndex].classList.remove('search-current');
  window._searchIndex = (window._searchIndex + 1) % m.length;
  m[window._searchIndex].classList.add('search-current');
  m[window._searchIndex].scrollIntoView({ behavior: 'smooth', block: 'center' });
  ReaderChannel.postMessage('search-index:' + window._searchIndex);
};

window.searchPrev = function() {
  var m = window._searchMatches;
  if (!m || m.length === 0) return;
  m[window._searchIndex].classList.remove('search-current');
  window._searchIndex = (window._searchIndex - 1 + m.length) % m.length;
  m[window._searchIndex].classList.add('search-current');
  m[window._searchIndex].scrollIntoView({ behavior: 'smooth', block: 'center' });
  ReaderChannel.postMessage('search-index:' + window._searchIndex);
};

window.searchClear = function() {
  var marks = document.querySelectorAll('.search-match');
  marks.forEach(function(mk) {
    var p = mk.parentNode;
    p.replaceChild(document.createTextNode(mk.textContent), mk);
    p.normalize();
  });
  window._searchMatches = [];
  window._searchIndex = -1;
};

// ── Highlight system ──────────────────────────────────────────
// Listen for text selection changes
var selectionTimeout;
document.addEventListener('selectionchange', function() {
  clearTimeout(selectionTimeout);
  selectionTimeout = setTimeout(function() {
    var sel = window.getSelection();
    if (sel && sel.toString().trim().length > 0 && sel.rangeCount > 0) {
      var range = sel.getRangeAt(0);
      // Calculate text offset within the body
      var preRange = document.createRange();
      preRange.selectNodeContents(document.body);
      preRange.setEnd(range.startContainer, range.startOffset);
      var startOffset = preRange.toString().length;
      var endOffset = startOffset + sel.toString().length;
      ReaderChannel.postMessage('selection:' + JSON.stringify({
        text: sel.toString().trim(),
        startOffset: startOffset,
        endOffset: endOffset
      }));
    } else {
      ReaderChannel.postMessage('selection-cleared');
    }
  }, 300);
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
    mark.style.setProperty('background-color', color, 'important');
    mark.style.setProperty('border-radius', '2px', 'important');
    mark.style.setProperty('padding', '1px 0', 'important');
    try {
      range.surroundContents(mark);
    } catch(e) {
      // If surroundContents fails (partial overlap), use extractContents
      var frag = range.extractContents();
      mark.appendChild(frag);
      range.insertNode(mark);
    }
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
