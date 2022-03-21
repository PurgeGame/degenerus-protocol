<script setup>
import MetaMaskConnection from "./components/MetaMaskConnection.vue";
import MainUserInterface from "./components/MainUserInterface.vue";
import { wallet } from "./store.js";
</script>

<template>
  <MetaMaskConnection />
  <div v-if="wallet.address">
    <MainUserInterface />
  </div>
</template>
