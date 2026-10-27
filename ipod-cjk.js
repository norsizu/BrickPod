// ipod-cjk.js — 中文显示修复（我写的，非 Apple 代码）
//
// 问题：iPod 屏幕字体 ChicagoKare 没有任何中文字形（解剖 woff2：214 个字形，
// CJK 覆盖为 0），中文回退到系统中文字体（如 PingFang SC，行度量约 1.42em，
// 26px 字号自然行高 37px）。菜单行是固定 height:26px + line-height:26px +
// overflow:hidden，中文字形上下被裁掉几像素；英文用 ChicagoKare 本尊、
// 墨迹小，永远没事。这也是为什么调字号救不了——裁剪比例恒定。
//
// 方案：文档级注册一个度量收紧的本地字体，只劫持 CJK 码位（unicode-range），
// 中文以 86% 大小渲染、行高压回 26.8px；英文数字继续走 ChicagoKare 原样。
//
// 两个 Chrome 的坑（都踩过了）：
//   1. @font-face 写进 Shadow DOM 的 <style> 不会注册，必须放文档级
//   2. local() 用字体家族名（"PingFang SC"）会 error，必须用 PostScript 名
(function () {
  var FACE = [
    '@font-face {',
    '  font-family: "IPOD-CJK";',
    '  src: local("PingFangSC-Regular"), local("HiraginoSansGB-W3"), local("STHeitiSC-Light");',
    '  size-adjust: 86%;',
    '  ascent-override: 94%;',
    '  descent-override: 26%;',
    '  unicode-range: U+3000-303F, U+3040-30FF, U+3130-318F, U+31F0-31FF, U+3400-4DBF,',
    '                 U+4E00-9FFF, U+AC00-D7AF, U+F900-FAFF, U+FE30-FE4F, U+FF00-FFEF;',
    '}'
  ].join('\n');
  var docStyle = document.createElement('style');
  docStyle.textContent = FACE;
  document.head.appendChild(docStyle);

  var OVERRIDE = '.ipod-screen{font-family:"IPOD-CJK",ChicagoKare,Krungthep,system-ui,sans-serif !important}';

  function inject(el) {
    if (!el || !el.shadowRoot) return false;
    if (!el.__cjkStyle) {
      var style = document.createElement('style');
      style.textContent = OVERRIDE;
      el.shadowRoot.appendChild(style);
      el.__cjkStyle = style;
    }
    return true;
  }
  function check() {
    var els = document.querySelectorAll('web-music-ipod');
    var ready = els.length > 0;
    els.forEach(function (el) { if (!inject(el)) ready = false; });
    return ready;
  }
  // 组件升级是异步的：轮询 + whenDefined + DOM 变化三种途径兜底，
  // 覆盖静态 HTML（widget.html）和动态挂载（镜像页）两种场景
  if (window.customElements && customElements.whenDefined) {
    customElements.whenDefined('web-music-ipod').then(check).catch(function () {});
  }
  var timer = setInterval(function () { if (check()) clearInterval(timer); }, 250);
  setTimeout(function () { clearInterval(timer); }, 30000);
  new MutationObserver(check)
    .observe(document.documentElement, { childList: true, subtree: true });
})();
