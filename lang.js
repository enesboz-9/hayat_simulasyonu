(function(){
  var saved=null;try{saved=localStorage.getItem('lang')}catch(e){}
  var l=saved||((navigator.language||'en').toLowerCase().indexOf('tr')===0?'tr':'en');
  function set(x){document.documentElement.lang=x;try{localStorage.setItem('lang',x)}catch(e){}
    document.querySelectorAll('.lang button').forEach(function(b){b.classList.toggle('on',b.dataset.set===x)});}
  document.addEventListener('DOMContentLoaded',function(){
    document.querySelectorAll('.lang button').forEach(function(b){b.addEventListener('click',function(){set(b.dataset.set)})});
    set(l);});
  document.documentElement.lang=l;
})();
