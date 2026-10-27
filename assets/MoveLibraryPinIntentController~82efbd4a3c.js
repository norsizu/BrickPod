import{ab as a,a8 as o}from"./index~ea66e33958.js";import{c as i,m as s}from"./libraryPinsAPI~c9fc5123b8.js";const p={$intentKind:a.Name,async perform(t,n){const{itemId:e}=t;try{const r=await i(e,t.after,n);return{pins:await s(r,n),status:o.SUCCESS}}catch(r){throw new Error(`an error occurred at MoveLibraryPinIntentController: ${r}`)}}};export{p as MoveLibraryPinIntentController};

