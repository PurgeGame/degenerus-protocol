<!-- Page header and grid layout for 3 child columns 

  TO DO
  --------------------
  Header links
  Fetch owned and burned NFT data, pass as props to center & left components
  Connect to Discord (possibly in another component)
  Referral code field (possibly in another component)
-->

<script setup>
import { ref, onMounted } from "vue";
import UserInterfaceLeft from "./UserInterfaceLeft.vue";
import UserInterfaceMiddle from "./UserInterfaceMiddle.vue";
import UserInterfaceRight from "./UserInterfaceRight.vue";
import { wallet } from "../store.js";

const middleColumn = ref(null);

const onClickDisconnect = () => {
  // Fake disconnect, because MetaMask won't allow a real one from an app
  wallet.address = null;
};

onMounted(() => {
  // Bring the middle column into view on page load. For small screens.
  middleColumn.value.scrollIntoView({ inline: "start" });
});
</script>

<template>
  <div class="flex flex-col h-screen overscroll-none">
    <div class="static bg-black bg-opacity-50">
      header
      <button
        @click="onClickDisconnect()"
        class="
          float-right
          m-1
          px-4
          md:py-1
          bg-black
          rounded-md
          hover:text-amber-400 hover:ring-1
          ring-amber-500
        "
      >
        <img src="/metamask-fox.svg" class="inline scale-75" />
        {{ wallet.address.substring(0, 5) }}...{{
          wallet.address.substring(38)
        }}
      </button>
    </div>
    <div
      class="
        grow
        overflow-x-scroll
        lg:overflow-x-auto
        overflow-hidden
        snap-mandatory snap-x
        lg:snap-none
      "
    >
      <div
        class="
          grid grid-cols-3
          h-full
          w-[300vw]
          md:w-[150vw]
          lg:w-full
          touch-pan-x
        "
      >
        <div class="snap-start snap-always h-full overflow-hidden">
          <UserInterfaceLeft />
        </div>
        <div
          ref="middleColumn"
          class="snap-start snap-always h-full overflow-auto"
        >
          <UserInterfaceMiddle />
        </div>
        <div class="snap-end snap-always h-full overflow-auto">
          <UserInterfaceRight />
        </div>
      </div>
    </div>
  </div>
</template>
