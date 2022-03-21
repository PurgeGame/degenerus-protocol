<!-- 
  TO DO
  --------------------
  Update logo to current
  Make 'Mint' button display conditional, based on... ?
  Table with owned traits, # purged, $ value
  Connect Discord button & Referral Code field in this column?
-->

<script setup>
</script>

<template>
  <div class="relative h-full mx-2">
    <img src="/logo-bg-trans.png" class="w-full bg-black p-2" />
    <span class="bg-black px-3">Season 1</span><br />
    <button
      class="
        block
        bg-black
        mx-auto
        my-12
        px-4
        py-2
        rounded-lg
        text-xl text-amber-500
        border border-amber-600
        hover:text-amber-400 hover:ring
        ring-amber-500
        font-bold
      "
    >
      Mint Game Piece
    </button>
    <div
      class="block bg-black w-auto p-4 border-2 border-red-900 rounded-lg"
    ></div>

    <div class="absolute bottom-0 w-full my-2 text-center lg:hidden">
      Traits <img src="/swipe.png" class="inline px-1" /> NFT's
    </div>
  </div>
</template>