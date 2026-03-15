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

document.body.addEventListener('click', function(e) {
  var now = Date.now();

  // Check for double-tap on TTS paragraph/sentence FIRST
  // (before selection check, so browser's double-click text selection doesn't interfere)
  var target = e.target.closest('[data-para]');

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
window.ttsHighlightParagraph = function(index) {
  // Remove previous highlight
  var prev = document.querySelector('.tts-highlight');
  if (prev) prev.classList.remove('tts-highlight');
  
  // Find paragraph by data-para attribute
  var el = document.querySelector('[data-para="' + index + '"]');
  if (el) {
    el.classList.add('tts-highlight');
    el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }
};

window.ttsHighlightSentence = function(paraIndex, sentIndex) {
  // Remove previous highlight
  var prev = document.querySelector('.tts-highlight');
  if (prev) prev.classList.remove('tts-highlight');
  
  // Find sentence by data-para and data-sent attributes
  var el = document.querySelector('[data-para="' + paraIndex + '"][data-sent="' + sentIndex + '"]');
  if (el) {
    el.classList.add('tts-highlight');
    el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  } else {
    // Fallback to paragraph highlight if no sentence span found
    window.ttsHighlightParagraph(paraIndex);
  }
};

window.ttsClearHighlight = function() {
  var prev = document.querySelector('.tts-highlight');
  if (prev) prev.classList.remove('tts-highlight');
};

// Scroll listener to update Flutter state
var scrollTimeout;
window.addEventListener('scroll', function() {
  clearTimeout(scrollTimeout);
  scrollTimeout = setTimeout(function() {
    ReaderChannel.postMessage('scroll:' + window.scrollY);
  }, 200);
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
