<!-- 
  TO DO
  --------------------
  Create background image and populate for burned trait tickets
  Display NFT's owned with multiple selection options to burn or sell
-->

<script setup>
const windowAlert = () => {
  window.alert("lol I don't do anything");
};

const sellNFT = () => {
  window.open("https://opensea.io/", "_blank");
};
</script>

<template>
  <div class="px-8">
    <p class="mt-10 text-lg text-center font-bold">Your tickets and NFTs</p>
    <hr />
    <div
      class="
        m-8
        bg-gradient-to-br
        from-amber-600
        to-amber-300
        border border-amber-500
      "
    >
      <p class="text-center text-black text-xl font-black py-4">
        A very valuable <br />
        prize ticket
      </p>
    </div>
    <div
      class="
        m-8
        bg-gradient-to-br
        from-amber-600
        to-amber-300
        border border-amber-500
      "
    >
      <p class="text-center text-black text-xl font-black py-4">
        Another very valuable <br />
        prize ticket
      </p>
    </div>
    <hr />
    <div
      class="
        mx-8
        mt-8
        bg-gradient-to-br
        from-zinc-500
        to-zinc-400
        aspect-square
        rounded-md
      "
    >
      <p class="text-center text-black text-xl font-black py-16">
        An NFT with <br />
        all the best traits
      </p>
    </div>
    <div class="mx-8">
      <button
        class="
          float-left
          bg-black
          mt-2
          px-4
          py-1
          rounded-md
          text-amber-500
          hover:ring
          ring-amber-500
        "
        @click="windowAlert()"
      >
        🔥 Purge 🔥
      </button>
      <button
        class="
          float-right
          bg-black
          mt-2
          px-4
          py-1
          rounded-md
          text-amber-500
          hover:ring
          ring-amber-500
        "
        @click="sellNFT()"
      >
        💰 &nbsp;Sell&nbsp; 💰
      </button>
    </div>
  </div>
</template>