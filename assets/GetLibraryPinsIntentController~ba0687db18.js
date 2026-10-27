import{a7 as n,a8 as e}from"./index~ea66e33958.js";import{r as a,m as i}from"./libraryPinsAPI~c9fc5123b8.js";const y={$intentKind:n.Name,async perform(s,t){try{const r=await a(t);return{pins:await i(r,t),status:e.SUCCESS}}catch(r){throw new Error(`an error occurred at GetLibraryPinsIntentController: ${r}`)}}};export{y as GetLibraryPinsIntentController};

